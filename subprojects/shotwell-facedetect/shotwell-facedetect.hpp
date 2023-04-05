/* 
 * Copyright 2018 Narendra A (narendra_m_a(at)yahoo dot com)
 * 
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 *
 * Header file for facedetect/recognition routines
 */

#pragma once

#include <opencv2/core/core.hpp>

#include <gio/gio.h>

#include <vector>

struct FaceRect {
    FaceRect()
      : vec(128, 0)
    {
    }
    float x{ 0.0F };
    float y{ 0.0F };
    float width{ 0.0F };
    float height{ 0.0F };
    std::vector<double> vec;

    GVariant *serialize() const;
};

bool loadNet(const cv::String& netFile);
std::vector<FaceRect> detectFaces(const cv::String& inputName, double scale, bool infer);
