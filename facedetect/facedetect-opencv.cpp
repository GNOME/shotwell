#include "shotwell-facedetect.hpp"

// Detect faces in a photo
std::vector<FaceRect> detectFaces(cv::String inputName, cv::String cascadeName, double scale) {
    cv::CascadeClassifier cascade;
	if (!cascade.load(cascadeName)) {
        std::cout << "error;Could not load classifier cascade. Filename: \"" << cascadeName << "\"" << std::endl;
	}

	if (inputName.empty()) {
        std::cout << "error;You must specify the file to process." << std::endl;
	}

    cv::Mat img = cv::imread(inputName, 1);
	if (img.empty()) {
        std::cout << "error;Could not load the file to process. Filename: \"" << inputName << "\"" << std::endl;
	}
    
    cv::Mat gray;
    cvtColor(img, gray, CV_BGR2GRAY);

    cv::Mat smallImg(cvRound(img.rows / scale), cvRound(img.cols / scale), CV_8UC1);
    cv::Size smallImgSize = smallImg.size();

    cv::resize(gray, smallImg, smallImgSize, 0, 0, cv::INTER_LINEAR);
    cv::equalizeHist(smallImg, smallImg);

    std::vector<cv::Rect> faces;
    cascade.detectMultiScale(smallImg, faces, 1.1, 2, CV_HAAR_SCALE_IMAGE, cv::Size(30, 30));

    std::vector<FaceRect> scaled;
    for (std::vector<cv::Rect>::const_iterator r = faces.begin(); r != faces.end(); r++) {
        FaceRect i;
        i.x = (float) r->x / smallImgSize.width;
        i.y = (float) r->y / smallImgSize.height;
        i.width = (float) r->width / smallImgSize.width;
        i.height = (float) r->height / smallImgSize.height;
        scaled.push_back(i);
    }

    return scaled;
}

// Load network into global var
bool loadNet(cv::String netFile) {
    try {
        faceRecogNet = cv::dnn::readNetFromTorch(netFile);
    } catch(cv::Exception e) {
        std::cout << "File load failed: " << e.msg << std::endl;
        return false;
    }
    if (faceRecogNet.empty()) {
        std::cout << "Loading net " << netFile << " failed!" << std::endl;
        return false;
    } else {
        std::cout << "Loaded " << netFile << std::endl;
        return true;
    }
}

// Face to vector convertor
// Adapted from OpenCV example:
// https://github.com/opencv/opencv/blob/master/samples/dnn/js_face_recognition.html
std::vector<double> faceToVec(cv::String inputName) {
    std::vector<double> ret;
    cv::Mat img = imread(inputName, 1);
	if (img.empty()) {
        std::cout << "error;Could not load the file to process. Filename: \"" << inputName << "\"" << std::endl;
        return ret;
	}

    cv::Mat smallImg(96, 96, CV_8UC1);
    cv::Size smallImgSize = smallImg.size();
    cv::resize(img, smallImg, smallImgSize, 0, 0, cv::INTER_LINEAR);

    // Generate 128 element face vector using DNN
    cv::Mat blob = cv::dnn::blobFromImage(smallImg, 1.0 / 255, smallImgSize,
                                          cv::Scalar(), true, false);
    faceRecogNet.setInput(blob);
    std::cout << "Starting recognition on " << inputName << " blob height " <<
        blob.size().height << " width " << blob.size().width << std::endl;
    cv::Mat vec = faceRecogNet.forward();
    std::cout << "Recognition done!" << std::endl;
    // Return vector
    ret.assign((double*)vec.datastart, (double*)vec.dataend);
    return ret;
}
