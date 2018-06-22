/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * Copyright 2018 Narendra Acharya <narendra_m_a(at)yahoo(dot)com>
 * 
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

typedef struct {
  float x;
  float y;
  float width;
  float height;
} FaceRect;

int detectFaces(const char *inputName, const char *cascadeName, double scale,
                FaceRect **rects, int *numFaces);

