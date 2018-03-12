/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

#include "shotwell-graphics-processor.h"

static inline void _pixel_transformer_apply_transformations (PixelTransformer* self, RGBAnalyticPixel* p, RGBAnalyticPixel* result) {
    PixelFormat current_format = PIXEL_FORMAT_RGB;
    RGBAnalyticPixel p_rgb = {p->red, p->green, p->blue };
    HSVAnalyticPixel p_hsv = {0.0f, 0.0f, 0.0f};
    gint i = 0;

    for (i = 0; i < self->optimized_slots_used; i++) {
        PixelTransformation* trans = NULL;
        PixelFormat preferred_format;

        trans = self->optimized_transformations[i];
        preferred_format = pixel_transformation_get_preferred_format (trans);
        if (preferred_format == PIXEL_FORMAT_RGB) {
            RGBAnalyticPixel _tmp14_ = {0};
            if (current_format == PIXEL_FORMAT_HSV) {
                hsv_analytic_pixel_to_rgb (&p_hsv, &p_rgb);
                current_format = PIXEL_FORMAT_RGB;
            }
            pixel_transformation_transform_pixel_rgb (trans, &p_rgb, &_tmp14_);
            p_rgb.red =_tmp14_.red;
            p_rgb.green =_tmp14_.green;
            p_rgb.blue =_tmp14_.blue;
        } else {
            HSVAnalyticPixel _tmp19_ = {0};
            if (current_format == PIXEL_FORMAT_RGB) {
                rgb_analytic_pixel_to_hsv (&p_rgb, &p_hsv);
                current_format = PIXEL_FORMAT_HSV;
            }
            pixel_transformation_transform_pixel_hsv (trans, &p_hsv, &_tmp19_);
            p_hsv.hue = _tmp19_.hue;
            p_hsv.saturation = _tmp19_.saturation;
            p_hsv.light_value = _tmp19_.light_value;
        }
    }

    if (current_format == PIXEL_FORMAT_HSV) {
        hsv_analytic_pixel_to_rgb (&p_hsv, &p_rgb);
    }

    result->red = p_rgb.red;
    result->green = p_rgb.green;
    result->blue = p_rgb.blue;
}

void pixel_transformer_apply_transformations (PixelTransformer* self, RGBAnalyticPixel* p, RGBAnalyticPixel* result) {
    _pixel_transformer_apply_transformations (self, p, result);
}

void pixel_transformer_apply_transformation (PixelTransformer* self,
                                             guint row,
                                             gint rowstride,
                                             gint rowbytes,
                                             gint n_channels,
                                             guchar* source_pixels, int source_pixels_length1,
                                             guchar* dest_pixels, int dest_pixels_length1) {
    guint row_start_index = row * rowstride;
    guint row_end_index = row_start_index + rowbytes;
    guint i = 0;

    for (i = row_start_index; i < row_end_index; i += n_channels) {
        RGBAnalyticPixel current_pixel = { rgb_lookup_table[source_pixels[i]],
                                           rgb_lookup_table[source_pixels[i+1]],
                                           rgb_lookup_table[source_pixels[i+2]] };
        RGBAnalyticPixel transformed_pixel = { 0.0f, 0.0f, 0.0f };
        _pixel_transformer_apply_transformations (self, &current_pixel, &transformed_pixel);
        dest_pixels[i] = (guchar) (transformed_pixel.red * 255.0f);
        dest_pixels[i+1] = (guchar) (transformed_pixel.green * 255.0f);
        dest_pixels[i+2] = (guchar) (transformed_pixel.blue * 255.0f);
    }
}

void hsv_analytic_pixel_to_rgb (HSVAnalyticPixel *self, RGBAnalyticPixel* result) {
    if (self->saturation == 0.0f) {
        result->red = self->light_value;
        result->green = self->light_value;
        result->blue = self->light_value;

        return;
    }

    float hue_denorm = self->hue * 360.0f;
    if (hue_denorm == 360.0f)
        hue_denorm = 0.0f;

    float hue_hexant = hue_denorm / 60.0f;
    int hexant_i_part = (int) hue_hexant;
    float hexant_f_part = hue_hexant - ((float) hexant_i_part);

    float p = self->light_value * (1.0f - self->saturation);
    float q = self->light_value * (1.0f - (self->saturation * hexant_f_part));
    float t = self->light_value * (1.0f - (self->saturation * (1.0f - hexant_f_part)));

    switch (hexant_i_part) {
        case 0:
            result->red = self->light_value; result->green = t; result->blue = p;
        break;
        case 1:
            result->red = q; result->green = self->light_value; result->blue = p;
        break;
        case 2:
            result->red = p; result->green = self->light_value; result->blue = t;
        break;
        case 3:
            result->red = p; result->green = q; result->blue = self->light_value;
        break;
        case 4:
            result->red = t; result->green = p; result->blue = self->light_value;
        break;
        case 5:
            result->red = self->light_value; result->green = p; result->blue = q;
        break;
        default:
            g_assert_not_reached();
    }
}

void hsv_analytic_pixel_init_from_rgb (HSVAnalyticPixel *self, RGBAnalyticPixel* p) {
    gfloat max_component = MAX(MAX(p->red, p->green), p->blue);
    gfloat min_component = MIN(MIN(p->red, p->green), p->blue);

    self->light_value = max_component;
    gfloat delta = max_component - min_component;
    self->saturation = (max_component != 0.0f) ? ((delta) / max_component) : 0.0f;
    if (self->saturation == 0.0f) {
        self->hue = 0.0f;

        return;
    }

    if (p->red == max_component) {
        self->hue = (p->green - p->blue) / delta;
    } else if (p->green == max_component) {
        self->hue = 2.0f + ((p->blue - p->red) / delta);
    } else if (p->blue == max_component) {
        self->hue = 4.0f + ((p->red - p->green) / delta);
    }

    self->hue *= 60.0f;
    if (self->hue < 0.0f) {
        self->hue += 360.0f;
    }

    self->hue /= 360.0f;
    self->hue = CLAMP(self->hue, 0.0f, 1.0f);
    self->saturation = CLAMP(self->saturation, 0.0f, 1.0f);
    self->light_value = CLAMP(self->light_value, 0.0f, 1.0f);
}

void rgb_transformation_real_transform_pixel_rgb (PixelTransformation* base, RGBAnalyticPixel* p, RGBAnalyticPixel* result) {
    RGBTransformation *self = RGB_TRANSFORMATION(base);
    result->red = CLAMP(p->red * self->matrix_entries[0] +
                        p->green * self->matrix_entries[1] +
                        p->blue * self->matrix_entries[2] +
                                  self->matrix_entries[3], 0.0f, 1.0f);
    result->green = CLAMP(p->red * self->matrix_entries[4] +
                          p->green * self->matrix_entries[5] +
                          p->blue * self->matrix_entries[6] +
                                    self->matrix_entries[7], 0.0f, 1.0f);
    result->blue = CLAMP(p->red * self->matrix_entries[8] +
                         p->green * self->matrix_entries[9] +
                         p->blue * self->matrix_entries[10] +
                                   self->matrix_entries[11], 0.0f, 1.0f);
}


void hsv_transformation_real_transform_pixel_hsv (PixelTransformation* base, HSVAnalyticPixel* pixel, HSVAnalyticPixel* result) {
    HSVTransformation *self = HSV_TRANSFORMATION(base);
    result->hue = pixel->hue;
    result->saturation = pixel->saturation;
    result->light_value = CLAMP(self->remap_table[(int) (pixel->light_value * 255.0f)], 0.0f, 1.0f);
}
