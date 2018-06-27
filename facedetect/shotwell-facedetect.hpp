/* 
 * Copyright 2018 Narendra A (narendra_m_a(at)yahoo dot com)
 * 
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 *
 * Header file for facedetect/recognition routines
 */

#include "opencv2/objdetect/objdetect.hpp"
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/imgproc/imgproc.hpp"

#include <iostream>
#include <stdio.h>

typedef struct {
    float x, y, width, height;
} FaceRect;

using namespace std;
using namespace cv;

vector<FaceRect> detectFaces(String inputName, String cascadeName, double scale);
int trainFaces(vector<String> images, vector<String> labels, String modelFile);
vector<pair<String, double>> recogniseFace(String image, String modelFile);
