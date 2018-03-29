/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * Copyright 2011 Valentín Barros Puertas <valentin(at)sanva(dot)net>
 * Copyright 2018 Ricardo Fantin da Costa <ricardofantin(at)gmail(dot)com>
 * 
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

#include "opencv2/objdetect/objdetect.hpp"
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/imgproc/imgproc.hpp"

#include <iostream>
#include <stdio.h>

using namespace std;
using namespace cv;

void help() {

	cout <<
		"Usage:" << endl <<
		"./facedetect --cascade=<cascade_path> "
		"--scale=<image scale greater or equal to 1, try 1.3 for example> "
		"filename" << endl << endl <<
		"Example:" << endl <<
		"./facedetect --cascade=\"./data/haarcascades/haarcascade_frontalface_alt.xml\" "
		"--scale=1.3 ./photo.jpg" << endl << endl <<
		"Using OpenCV version " << CV_VERSION << endl;

}

void detectFaces(Mat &img, CascadeClassifier &cascade, double scale) {

	Mat gray;
	cvtColor(img, gray, CV_BGR2GRAY);

	Mat smallImg(cvRound(img.rows / scale), cvRound(img.cols / scale), CV_8UC1);
	Size smallImgSize = smallImg.size();

	resize(gray, smallImg, smallImgSize, 0, 0, INTER_LINEAR);
	equalizeHist(smallImg, smallImg);

	vector<Rect> faces;
	cascade.detectMultiScale(smallImg, faces, 1.1, 2, CV_HAAR_SCALE_IMAGE, Size(30, 30));

	int i = 0;
	for (vector<Rect>::const_iterator r = faces.begin(); r != faces.end(); r++, i++) {

		printf(
			"face;x=%f&y=%f&width=%f&height=%f\n",
			(float) r->x / smallImgSize.width,
			(float) r->y / smallImgSize.height,
			(float) r->width / smallImgSize.width,
			(float) r->height / smallImgSize.height
		);

	}

}

int main(int argc, const char** argv) {

	const std::string scaleOpt = "--scale=";
	size_t scaleOptLen = scaleOpt.length();
	const std::string cascadeOpt = "--cascade=";
	size_t cascadeOptLen = cascadeOpt.length();

	std::string cascadeName, inputName;
	double scale = 1;

	for (int i = 1; i < argc; i++) {

		if (cascadeOpt.compare(0, cascadeOptLen, argv[i], cascadeOptLen) == 0) {

			cascadeName.assign(argv[i] + cascadeOptLen);

		} else if (scaleOpt.compare(0, scaleOptLen, argv[i], scaleOptLen) == 0) {

			if (!sscanf(argv[i] + scaleOpt.length(), "%lf", &scale) || scale < 1)
				scale = 1;

		} else if (argv[i][0] == '-') {

			cout << "warning;Unknown option " << argv[i] << endl;

		} else
			inputName.assign(argv[i]);

	}

	if (cascadeName.empty()) {

		cout << "error;You must specify the cascade." << endl;
		help();

		return -1;

	}

	CascadeClassifier cascade;

	if (!cascade.load(cascadeName)) {

		cout << "error;Could not load classifier cascade. Filename: \"" << cascadeName << "\"" << endl;

		return -1;
	}

	if (inputName.empty()) {

		cout << "error;You must specify the file to process." << endl;
		help();

		return -1;

	}

	Mat image = imread(inputName, 1);

	if (image.empty()) {

		cout << "error;Could not load the file to process. Filename: \"" << inputName << "\"" << endl;

		return -1;

	}

	detectFaces(image, cascade, scale);

	return 0;

}
