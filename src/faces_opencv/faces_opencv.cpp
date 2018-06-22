/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * Copyright 2011 Valentín Barros Puertas <valentin(at)sanva(dot)net>
 * Copyright 2018 Ricardo Fantin da Costa <ricardofantin(at)gmail(dot)com>
 * Copyright 2018 Narendra Acharya <narendra_m_a(at)yahoo(dot)com>
 * 
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

#include "opencv2/objdetect/objdetect.hpp"
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/imgproc/imgproc.hpp"
extern "C" {
#include "faces_opencv.h"
}
#include <iostream>
#include <stdio.h>

using namespace std;
using namespace cv;

// OpenCV calls in C++
vector<FaceRect> ocvDetectFaces(Mat &img, CascadeClassifier &cascade, double scale) {
  Mat gray;
  cvtColor(img, gray, CV_BGR2GRAY);

  Mat smallImg(cvRound(img.rows / scale), cvRound(img.cols / scale), CV_8UC1);
  Size smallImgSize = smallImg.size();

  resize(gray, smallImg, smallImgSize, 0, 0, INTER_LINEAR);
  equalizeHist(smallImg, smallImg);

  vector<Rect> faces;
  cascade.detectMultiScale(smallImg, faces, 1.1, 2, CV_HAAR_SCALE_IMAGE, Size(30, 30));
  vector<FaceRect> ret;
  for (vector<Rect>::const_iterator r = faces.begin(); r != faces.end(); r++) {
    FaceRect rect;
    rect.x = ((float)r->x / smallImgSize.width);
    rect.y = ((float)r->y / smallImgSize.height);
    rect.width = ((float)r->width / smallImgSize.width);
    rect.height = ((float)r->height / smallImgSize.height);
    ret.push_back(rect);
  }
  
  return ret;
}

// Exported interface to C with simple operands
extern "C" {
  int detectFaces(const char *inputName, const char *cascadeName, double scale,
                  FaceRect **rects, int *numFaces) {
    CascadeClassifier cascade;
    
    *numFaces = 0; // Zero length array
    if (!cascade.load(cascadeName)) {
      cout << "error;Could not load classifier cascade. Filename: \"" << cascadeName << "\"" << endl;
      return -1;
	}

    Mat image = imread(inputName, 1);
    if (image.empty()) {
      cout << "error;Could not load the file to process. Filename: \"" << inputName << "\"" << endl;
      return -1;
    }

    vector<FaceRect> faces;
    faces = ocvDetectFaces(image, cascade, scale);
    *rects = (FaceRect *)malloc(sizeof(FaceRect) * faces.size());

    int i = 0;
    for (vector<FaceRect>::const_iterator r = faces.begin(); r != faces.end(); r++, i++) {
      (*rects)[i].x = r->x; (*rects)[i].y = r->y;
      (*rects)[i].width = r->width; (*rects)[i].height = r->height;
    }
    *numFaces = i;
    
    return 0;
  }
}
