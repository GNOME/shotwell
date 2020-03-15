/* 
 * Copyright 2018 Narendra A (narendra_m_a(at)yahoo dot com)
 * 
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 *
 * Header file for facedetect/recognition routines
 */

#include <opencv2/core/core.hpp>
#include <opencv2/objdetect/objdetect.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#ifdef HAVE_OPENCV_DNN_HPP
#include <opencv2/dnn.hpp>
#endif

#include <iostream>
#include <stdio.h>
#include <algorithm>

typedef struct {
    float x, y, width, height;
    std::vector<double> vec;
} FaceRect;

// Global variable for DNN to generate vector out of face
#ifdef HAVE_OPENCV_DNN_HPP
static cv::dnn::Net faceRecogNet;
static cv::dnn::Net faceDetectNet;
#endif

bool loadNet(cv::String netFile);
std::vector<FaceRect> detectFaces(cv::String inputName, cv::String cascadeName, double scale, bool infer);
std::vector<cv::Rect> detectFacesMat(cv::Mat img);
std::vector<double> faceToVecMat(cv::Mat img);
std::vector<double> faceToVec(cv::String inputName);
