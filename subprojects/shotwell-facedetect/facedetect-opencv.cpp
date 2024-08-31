// SPDX-License-Identifier: LGPL-2.1-or-later

#include "shotwell-facedetect.hpp"

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/objdetect/objdetect.hpp>

#ifdef HAS_OPENCV_DNN
    #include <opencv2/dnn.hpp>
#endif

#include <iostream>
#include <string>
#include <filesystem>

// Global variable for DNN to generate vector out of face
#ifdef HAS_OPENCV_DNN
static cv::dnn::Net faceRecogNet;
static cv::dnn::Net faceDetectNet;
#endif

static cv::CascadeClassifier cascade;
static cv::CascadeClassifier cascade_profile;
static bool disableDnn{ true };

constexpr std::string_view PROTOTEXT_FILE{ "deploy.prototxt" };
constexpr std::string_view OPENFACE_RECOG_TORCH_NET{ "openface.nn4.small2.v1.t7" };
constexpr std::string_view RESNET_DETECT_CAFFE_NET{ "res10_300x300_ssd_iter_140000_fp16.caffemodel" };
constexpr std::string_view HAARCASCADE{ "haarcascade_frontalface_alt.xml" };
constexpr std::string_view HAARCASCADE_PROFILE{ "haarcascade_profileface.xml" };

std::vector<cv::Rect> detectFacesMat(const cv::Mat &img);
std::vector<double> faceToVecMat(const cv::Mat& img);

// Detect faces in a photo
std::vector<FaceRect> detectFaces(const cv::String &inputName, double scale, bool infer = false) {
    if(cascade.empty()) {
        g_warning("No cascade file loaded. Did you call loadNet()?");
        return {};
    }

	if (inputName.empty()) {
        g_warning("No file to process. aborting");
        return {};
        return {};
	}

    cv::Mat const img = cv::imread(inputName, 1);
	if (img.empty()) {
        g_warning("Failed to load the image file: %s", inputName.c_str());
        return {};
	}

    std::vector<cv::Rect> faces;
    cv::Size smallImgSize;

#ifdef HAS_OPENCV_DNN
    disableDnn = faceDetectNet.empty();
#else
    disableDnn = true;
#endif
    try {
        if (disableDnn) {
            // Classical face detection
            cv::Mat gray;
            cvtColor(img, gray, cv::COLOR_BGR2GRAY);

            scale = 1.0;
            cv::Mat smallImg(cvRound(img.rows / scale), cvRound(img.cols / scale), CV_8UC1);
            smallImgSize = smallImg.size();

            cv::resize(gray, smallImg, smallImgSize, 0, 0, cv::INTER_LINEAR);
            cv::equalizeHist(smallImg, smallImg);
            constexpr double SCALE_FACTOR_FRONTAL{ 1.1 };
            constexpr double SCALE_FACTOR_PROFILE{ 1.05 };
            constexpr int MIN_NEIGHBOURS{ 2 };
            constexpr int MIN_SIZE{ 30 };
            cascade.detectMultiScale (smallImg,
                                    faces,
                                    SCALE_FACTOR_FRONTAL,
                                    MIN_NEIGHBOURS,
                                    cv::CASCADE_SCALE_IMAGE,
                                    cv::Size (MIN_SIZE, MIN_SIZE));

            // Run the cascade for profile faces, if available
            if(not cascade_profile.empty()) {
                g_debug("Running haarcascade detection for profile faces");
                std::vector<cv::Rect> profiles;
                cascade_profile.detectMultiScale (smallImg,
                                                profiles,
                                                SCALE_FACTOR_PROFILE,
                                                MIN_NEIGHBOURS,
                                                cv::CASCADE_SCALE_IMAGE,
                                                cv::Size (MIN_SIZE, MIN_SIZE));
                if(not profiles.empty()) {
                    faces.insert(faces.end(), profiles.begin(), profiles.end());
                }

                // Duplicate all rectangles so we can safely run groupRectangles with minimum 1 on it - otherwise
                // OpenCV does weird things
                faces.insert(faces.end(), faces.begin(), faces.end());

                // Try to merge all overlapping rectangles
                cv::groupRectangles(faces, 1);
            }
        } else {
    #ifdef HAS_OPENCV_DNN
            // DNN based face detection
            faces = detectFacesMat(img);
            smallImgSize = img.size(); // Not using the small image here
    #endif
        }
    } catch (cv::Exception& ex) {
        g_warning("Face detection failed: %s", ex.what());
        return {};
    }

    std::vector<FaceRect> scaled;
    for (std::vector<cv::Rect>::const_iterator r = faces.begin(); r != faces.end(); r++) {
        FaceRect i;
        i.x = (float) r->x / smallImgSize.width;
        i.y = (float) r->y / smallImgSize.height;
        i.width = (float) r->width / smallImgSize.width;
        i.height = (float) r->height / smallImgSize.height;

#ifdef HAS_OPENCV_DNN
        try {
            if (infer && !faceRecogNet.empty()) {
                // Get colour image for vector generation
                cv::Mat colourImg;
                cv::resize(img, colourImg, smallImgSize, 0, 0, cv::INTER_LINEAR);
                i.vec = faceToVecMat(colourImg(*r)); // Run vector conversion on the face
            }
        } catch (cv::Exception& ex) {
            g_warning("Face recognition failed: %s", ex.what());
            i.vec = {};
        }
#endif
        scaled.push_back(i);
    }

    return scaled;
}

// Load network into global var
bool loadNet(const cv::String &baseDir)
{
    // Split baseDir into multiple search paths
    std::stringstream iss{ baseDir };
    std::string path;
    while(std::getline(iss, path, ':')) {
        g_debug("Looking for face detection data files in %s", path.c_str());

        std::filesystem::path const base_path{ path };

        auto haarcascade = base_path / HAARCASCADE;
        if(cascade.empty()) {
            cascade.load(haarcascade);
        }

        if(cascade.empty()) {
            g_info("%s not found", haarcascade.c_str());
        }

        auto haarcascade_profile = base_path / HAARCASCADE_PROFILE;
        if(cascade_profile.empty()) {
            cascade_profile.load(haarcascade_profile);
        }

        if(cascade_profile.empty()) {
            g_info("%s not found", haarcascade_profile.c_str());
        }

#if HAS_OPENCV_DNN

        if(faceDetectNet.empty()) {
            try {
                faceDetectNet =
                    cv::dnn::readNetFromCaffe(base_path / PROTOTEXT_FILE, base_path / RESNET_DETECT_CAFFE_NET);
            } catch(cv::Exception &e) {
                g_info("Failed to load face detect net: %s", e.what());
            }
        }

        if(faceRecogNet.empty()) {
            try {
                faceRecogNet = cv::dnn::readNetFromTorch(base_path / OPENFACE_RECOG_TORCH_NET);
            } catch(cv::Exception &e) {
                g_info("Failed to load face recognition net: %s", e.what());
            }
        }
#endif
    }

#if HAS_OPENCV_DNN
    // If there is no detection model, disable advanced face detection
    disableDnn = faceDetectNet.empty();

    if(faceRecogNet.empty()) {
        g_warning("Face recognition net not available, disabling recognition");
    }
#endif

    if (disableDnn && cascade.empty() && cascade_profile.empty()) {
       g_warning("No face detection method detected. Face detection fill not work.");
       return false; 
    }

    return true;
}

// Face detector
// Adapted from OpenCV example:
// https://github.com/opencv/opencv/blob/master/samples/dnn/js_face_recognition.html
std::vector<cv::Rect> detectFacesMat(const cv::Mat& img) {
    std::vector<cv::Rect> faces;
#ifdef HAS_OPENCV_DNN
    const cv::Mat blob = cv::dnn::blobFromImage(img, 1.0, cv::Size(128*8, 96*8),
                                          cv::Scalar(104, 177, 123, 0), false, false);
    faceDetectNet.setInput(blob);
    cv::Mat out = faceDetectNet.forward();
    // out is a 4D matrix [1 x 1 x n x 7]
    // n - number of results
    assert(out.dims == 4);
    int outIdx[4] = { 0, 0, 0, 0 };
    auto result_size = out.size[2];
    for (auto i = 0; i < result_size; i++) {
        outIdx[2] = i; outIdx[3] = 2;
        const auto confidence = out.at<float>(outIdx);
        outIdx[3]++;
        auto left = out.at<float>(outIdx) * (double)img.cols;
        outIdx[3]++;
        auto top = out.at<float>(outIdx) * (double)img.rows;
        outIdx[3]++;
        auto right = out.at<float>(outIdx) * (double)img.cols;
        outIdx[3]++;
        auto bottom = out.at<float> (outIdx) * (double)img.rows;
        left = std::clamp (left, 0.0, (double) img.cols - 1);
        right = std::clamp (right, 0.0, (double) img.cols - 1);
        bottom = std::clamp (bottom, 0.0, (double) img.rows - 1);
        top = std::clamp (top, 0.0, (double) img.rows - 1);

        constexpr double CONFIDENCE_THRESHOLD{ 0.98 };
        if (confidence > CONFIDENCE_THRESHOLD && left < right && top < bottom) {
            const cv::Rect rect (static_cast<int> (left),
                                 static_cast<int> (top),
                                 static_cast<int> (right - left),
                                 static_cast<int> (bottom - top));
            faces.push_back(rect);
        }
    }
#endif // HAS_OPENCV_DNN
    return faces;
}

// Face to vector converter
// Adapted from OpenCV example:
// https://github.com/opencv/opencv/blob/master/samples/dnn/js_face_recognition.html
#ifdef HAS_OPENCV_DNN
std::vector<double> faceToVecMat(const cv::Mat &img) {
    std::vector<double> ret;
    constexpr int SMALL_IMAGE_SIZE{ 96 };
    cv::Mat smallImg(SMALL_IMAGE_SIZE, SMALL_IMAGE_SIZE, CV_8UC1);
    const cv::Size smallImgSize = smallImg.size();

    cv::resize(img, smallImg, smallImgSize, 0, 0, cv::INTER_LINEAR);
    // Generate 128 element face vector using DNN
    constexpr double SCALE_FACTOR{ 1.0 / 255.0 };
    const cv::Mat blob = cv::dnn::blobFromImage (smallImg, SCALE_FACTOR, smallImgSize, cv::Scalar (), true, false);

    faceRecogNet.setInput(blob);
    cv::Mat vec = faceRecogNet.forward();
    // Return vector
    for (int i = 0; i < vec.rows; ++i) {
        ret.insert(ret.end(), vec.ptr<float>(i), vec.ptr<float>(i) + vec.cols);
    }
    return ret;
}
#endif
