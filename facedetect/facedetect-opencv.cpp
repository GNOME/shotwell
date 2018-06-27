#include "shotwell-facedetect.hpp"

using namespace std;
using namespace cv;

vector<FaceRect> detectFaces(String inputName, String cascadeName, double scale) {
	CascadeClassifier cascade;
	if (!cascade.load(cascadeName)) {
		cout << "error;Could not load classifier cascade. Filename: \"" << cascadeName << "\"" << endl;
	}

	if (inputName.empty()) {
		cout << "error;You must specify the file to process." << endl;
	}

	Mat img = imread(inputName, 1);
	if (img.empty()) {
		cout << "error;Could not load the file to process. Filename: \"" << inputName << "\"" << endl;
	}
    
    Mat gray;
    cvtColor(img, gray, CV_BGR2GRAY);

    Mat smallImg(cvRound(img.rows / scale), cvRound(img.cols / scale), CV_8UC1);
    Size smallImgSize = smallImg.size();

    resize(gray, smallImg, smallImgSize, 0, 0, INTER_LINEAR);
    equalizeHist(smallImg, smallImg);

    vector<Rect> faces;
    cascade.detectMultiScale(smallImg, faces, 1.1, 2, CV_HAAR_SCALE_IMAGE, Size(30, 30));

    vector<FaceRect> scaled;
    for (vector<Rect>::const_iterator r = faces.begin(); r != faces.end(); r++) {
        FaceRect i;
        i.x = (float) r->x / smallImgSize.width;
        i.y = (float) r->y / smallImgSize.height;
        i.width = (float) r->width / smallImgSize.width;
        i.height = (float) r->height / smallImgSize.height;
        scaled.push_back(i);
    }

    return scaled;
}
