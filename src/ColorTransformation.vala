/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public struct RGBAnalyticPixel {
    public float red;
    public float green;
    public float blue;
    
    public RGBAnalyticPixel() {
        red = 0.0f;
        green = 0.0f;
        blue = 0.0f;
    }
    
    public RGBAnalyticPixel.from_components(float red, float green,
        float blue) {
        this.red = red.clamp(0.0f, 1.0f);
        this.green = green.clamp(0.0f, 1.0f);
        this.blue = blue.clamp(0.0f, 1.0f);
    }
    
    public RGBAnalyticPixel.from_quantized_components(uchar red_quantized,
        uchar green_quantized, uchar blue_quantized) {
        this.red = ((float) red_quantized) / 255.0f;
        this.green = ((float) green_quantized) / 255.0f;
        this.blue = ((float) blue_quantized) / 255.0f;
    }
    
    public uchar quantized_red() {
        return (uchar)(red * 255.0f);
    }
    
    public uchar quantized_green() {
        return (uchar)(green * 255.0f);
    }
    
    public uchar quantized_blue() {
        return (uchar)(blue * 255.0f);
    }
    
    public static RGBAnalyticPixel get_pixbuf_pixel(owned Gdk.Pixbuf pixbuf,
        int x, int y) {
        assert((x >= 0) && (x < pixbuf.width));
        assert((y >= 0) && (y < pixbuf.height));
        
        int px_start_byte_offset = (y * pixbuf.rowstride) + (x *
            pixbuf.n_channels);
        
        unowned uchar[] pixel_data = pixbuf.get_pixels();
        
        return RGBAnalyticPixel.from_quantized_components(
            pixel_data[px_start_byte_offset],
            pixel_data[px_start_byte_offset + 1],
            pixel_data[px_start_byte_offset + 2]);
    }
    
    public static void set_pixbuf_pixel(owned Gdk.Pixbuf pixbuf,
        RGBAnalyticPixel pixel, int x, int y) {
        assert((x >= 0) && (x < pixbuf.width));
        assert((y >= 0) && (y < pixbuf.height));
        
        int px_start_byte_offset = (y * pixbuf.rowstride) + (x *
            pixbuf.n_channels);
        
        unowned uchar[] pixel_data = pixbuf.get_pixels();
        
        pixel_data[px_start_byte_offset] = pixel.quantized_red();
        pixel_data[px_start_byte_offset + 1] = pixel.quantized_green();
        pixel_data[px_start_byte_offset + 2] = pixel.quantized_blue();
    }    
}

public struct HSVAnalyticPixel {
    public float hue;
    public float saturation;
    public float light_value;

    public HSVAnalyticPixel() {
        hue = 0.0f;
        saturation = 0.0f;
        light_value = 0.0f;
    }

    public HSVAnalyticPixel.from_components(float hue, float saturation,
        float light_value) {
        this.hue = hue.clamp(0.0f, 1.0f);
        this.saturation = saturation.clamp(0.0f, 1.0f);
        this.light_value = light_value.clamp(0.0f, 1.0f);
    }
    
    public HSVAnalyticPixel.from_rgb(RGBAnalyticPixel p) {
        float max_component = float.max(float.max(p.red, p.green), p.blue);
        float min_component = float.min(float.min(p.red, p.green), p.blue);
        
        light_value = max_component;
        saturation = (max_component != 0.0f) ? ((max_component - min_component) /
            max_component) : 0.0f;
        
        if (saturation == 0.0f) {
            hue = 0.0f; /* hue is undefined in the zero saturation case */
        } else {
            float delta = max_component - min_component;
            if (p.red == max_component) {
                hue = (p.green - p.blue) / delta;
            } else if (p.green == max_component) {
                hue = 2.0f + ((p.blue - p.red) / delta);
            } else if (p.blue == max_component) {
                hue = 4.0f + ((p.red - p.green) / delta);
            }
            
            hue *= 60.0f;
            if (hue < 0.0f)
                hue += 360.0f;
            
            hue /= 360.0f; /* normalize hue */
        }
        
        hue = hue.clamp(0.0f, 1.0f);
        saturation = saturation.clamp(0.0f, 1.0f);
        light_value = light_value.clamp(0.0f, 1.0f);
    }
    
    public RGBAnalyticPixel to_rgb() {
        RGBAnalyticPixel result = RGBAnalyticPixel();

        if (saturation == 0.0f) {
            result.red = light_value;
            result.green = light_value;
            result.blue = light_value;
        } else {
            float hue_denorm = hue * 360.0f;
            if (hue_denorm == 360.0f)
                hue_denorm = 0.0f;
            
            float hue_hexant = hue_denorm / 60.0f;
            
            int hexant_i_part = (int) hue_hexant;
            
            float hexant_f_part = hue_hexant - ((float) hexant_i_part);
            
            /* the p, q, and t quantities from section 13.3 of Foley, et. al. */
            float p = light_value * (1.0f - saturation);
            float q = light_value * (1.0f - (saturation * hexant_f_part));
            float t = light_value * (1.0f - (saturation * (1.0f - hexant_f_part)));
            switch (hexant_i_part) {
                /* the (r, g, b) components of the output pixel are computed
                   from the light_value, p, q, and t quantities differently
                   depending on which "hexant" (1/6 of a full rotation) of the
                   HSV color cone the hue lies in. For example, if the hue lies
                   in the yellow hexant, the dominant channels in the output
                   are red and green, so we map relatively more of the light_value
                   into these colors than if, say, the hue were to lie in the
                   cyan hexant. See chapter 13 of Foley, et. al. for more
                   information. */
                case 0:
                    result.red = light_value;
                    result.green = t;
                    result.blue = p;
                break;

                case 1:
                    result.red = q;
                    result.green = light_value;
                    result.blue = p;
                break;

                case 2:
                    result.red = p;
                    result.green = light_value;
                    result.blue = t;
                break;

                case 3:
                    result.red = p;
                    result.green = q;
                    result.blue = light_value;
                break;
                
                case 4:
                    result.red = t;
                    result.green = p;
                    result.blue = light_value;
                break;

                case 5:
                    result.red = light_value;
                    result.green = p;
                    result.blue = q;
                break;
                
                default:
                    error("bad color hexant in HSV-to-RGB conversion");
                break;
            }
        }

        return result;
    }
}

public enum RGBTransformationKind {
    EXPOSURE,
    SATURATION,
    TINT,
    TEMPERATURE
}

public struct RGBTransformationInstance {
    public RGBTransformationKind kind;
    public float parameter;
}

public class RGBTransformation {
    /* matrix entries are stored in row-major; by default, the matrix formed
       by matrix_entries is the 4x4 identity matrix */
    protected float[] matrix_entries = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f };
    
    protected bool identity = true;

    public RGBTransformation() {
    }
    
    public bool is_identity() {
        return identity;
    }
    
    public RGBAnalyticPixel transform_pixel(RGBAnalyticPixel pixel) {
        float red_out = (pixel.red * matrix_entries[0]) +
            (pixel.green * matrix_entries[1]) +
            (pixel.blue * matrix_entries[2]) +
            matrix_entries[3];
        red_out = red_out.clamp(0.0f, 1.0f);

        float green_out = (pixel.red * matrix_entries[4]) +
            (pixel.green * matrix_entries[5]) +
            (pixel.blue * matrix_entries[6]) +
            matrix_entries[7];
        green_out = green_out.clamp(0.0f, 1.0f);

        float blue_out = (pixel.red * matrix_entries[8]) +
            (pixel.green * matrix_entries[9]) +
            (pixel.blue * matrix_entries[10]) +
            matrix_entries[11];
        blue_out = blue_out.clamp(0.0f, 1.0f);
        
        return RGBAnalyticPixel.from_components(red_out, green_out, blue_out);
    }
    
    public RGBTransformation compose_against(RGBTransformation transform) {
        RGBTransformation result = new RGBTransformation();
        
        /* row 0 */
        result.matrix_entries[0] =
            (matrix_entries[0] * transform.matrix_entries[0]) +
            (matrix_entries[1] * transform.matrix_entries[4]) +
            (matrix_entries[2] * transform.matrix_entries[8]) +
            (matrix_entries[3] * transform.matrix_entries[12]);

        result.matrix_entries[1] =
            (matrix_entries[0] * transform.matrix_entries[1]) +
            (matrix_entries[1] * transform.matrix_entries[5]) +
            (matrix_entries[2] * transform.matrix_entries[9]) +
            (matrix_entries[3] * transform.matrix_entries[13]);

        result.matrix_entries[2] =
            (matrix_entries[0] * transform.matrix_entries[2]) +
            (matrix_entries[1] * transform.matrix_entries[6]) +
            (matrix_entries[2] * transform.matrix_entries[10]) +
            (matrix_entries[3] * transform.matrix_entries[14]);

        result.matrix_entries[3] =
            (matrix_entries[0] * transform.matrix_entries[3]) +
            (matrix_entries[1] * transform.matrix_entries[7]) +
            (matrix_entries[2] * transform.matrix_entries[11]) +
            (matrix_entries[3] * transform.matrix_entries[15]);

        /* row 1 */
        result.matrix_entries[4] =
            (matrix_entries[4] * transform.matrix_entries[0]) +
            (matrix_entries[5] * transform.matrix_entries[4]) +
            (matrix_entries[6] * transform.matrix_entries[8]) +
            (matrix_entries[7] * transform.matrix_entries[12]);

        result.matrix_entries[5] =
            (matrix_entries[4] * transform.matrix_entries[1]) +
            (matrix_entries[5] * transform.matrix_entries[5]) +
            (matrix_entries[6] * transform.matrix_entries[9]) +
            (matrix_entries[7] * transform.matrix_entries[13]);

        result.matrix_entries[6] =
            (matrix_entries[4] * transform.matrix_entries[2]) +
            (matrix_entries[5] * transform.matrix_entries[6]) +
            (matrix_entries[6] * transform.matrix_entries[10]) +
            (matrix_entries[7] * transform.matrix_entries[14]);

        result.matrix_entries[7] =
            (matrix_entries[4] * transform.matrix_entries[3]) +
            (matrix_entries[5] * transform.matrix_entries[7]) +
            (matrix_entries[6] * transform.matrix_entries[11]) +
            (matrix_entries[7] * transform.matrix_entries[15]);

        /* row 2 */
        result.matrix_entries[8] =
            (matrix_entries[8] * transform.matrix_entries[0]) +
            (matrix_entries[9] * transform.matrix_entries[4]) +
            (matrix_entries[10] * transform.matrix_entries[8]) +
            (matrix_entries[11] * transform.matrix_entries[12]);

        result.matrix_entries[9] =
            (matrix_entries[8] * transform.matrix_entries[1]) +
            (matrix_entries[9] * transform.matrix_entries[5]) +
            (matrix_entries[10] * transform.matrix_entries[9]) +
            (matrix_entries[11] * transform.matrix_entries[13]);

        result.matrix_entries[10] =
            (matrix_entries[8] * transform.matrix_entries[2]) +
            (matrix_entries[9] * transform.matrix_entries[6]) +
            (matrix_entries[10] * transform.matrix_entries[10]) +
            (matrix_entries[11] * transform.matrix_entries[14]);

        result.matrix_entries[11] =
            (matrix_entries[8] * transform.matrix_entries[3]) +
            (matrix_entries[9] * transform.matrix_entries[7]) +
            (matrix_entries[10] * transform.matrix_entries[11]) +
            (matrix_entries[11] * transform.matrix_entries[15]);

        /* row 3 */
        result.matrix_entries[12] =
            (matrix_entries[12] * transform.matrix_entries[0]) +
            (matrix_entries[13] * transform.matrix_entries[4]) +
            (matrix_entries[14] * transform.matrix_entries[8]) +
            (matrix_entries[15] * transform.matrix_entries[12]);

        result.matrix_entries[13] =
            (matrix_entries[12] * transform.matrix_entries[1]) +
            (matrix_entries[13] * transform.matrix_entries[5]) +
            (matrix_entries[14] * transform.matrix_entries[9]) +
            (matrix_entries[15] * transform.matrix_entries[13]);

        result.matrix_entries[14] =
            (matrix_entries[12] * transform.matrix_entries[2]) +
            (matrix_entries[13] * transform.matrix_entries[6]) +
            (matrix_entries[14] * transform.matrix_entries[10]) +
            (matrix_entries[15] * transform.matrix_entries[14]);

        result.matrix_entries[15] =
            (matrix_entries[12] * transform.matrix_entries[3]) +
            (matrix_entries[13] * transform.matrix_entries[7]) +
            (matrix_entries[14] * transform.matrix_entries[11]) +
            (matrix_entries[15] * transform.matrix_entries[15]);
        
        if (!identity) {
            result.identity = false;
        }
        if (!transform.identity) {
            result.identity = false;
        }
        
        return result;
    }

    public static void transform_pixbuf(RGBTransformation transform,
        owned Gdk.Pixbuf pixbuf) {
        for (int j = 0; j < pixbuf.height; j++) {
            for (int i = 0; i < pixbuf.width; i++) {
            
                RGBAnalyticPixel pixel_ij =
                    RGBAnalyticPixel.get_pixbuf_pixel(pixbuf, i, j);

                RGBAnalyticPixel pixel_ij_transformed =
                    transform.transform_pixel(pixel_ij);
                
                RGBAnalyticPixel.set_pixbuf_pixel(pixbuf, pixel_ij_transformed,
                    i, j);
            }
        }
    }
    
    public static void transform_existing_pixbuf(RGBTransformation transform,
        owned Gdk.Pixbuf in_pixbuf, owned Gdk.Pixbuf out_pixbuf) {
        assert((in_pixbuf.width == out_pixbuf.width) && (in_pixbuf.height ==
            out_pixbuf.height));
        for (int j = 0; j < in_pixbuf.height; j++) {
            for (int i = 0; i < in_pixbuf.width; i++) {
            
                RGBAnalyticPixel pixel_ij =
                    RGBAnalyticPixel.get_pixbuf_pixel(in_pixbuf, i, j);

                RGBAnalyticPixel pixel_ij_transformed =
                    transform.transform_pixel(pixel_ij);
                
                RGBAnalyticPixel.set_pixbuf_pixel(out_pixbuf, pixel_ij_transformed,
                    i, j);
            }
        }
    }
}
 
public class ExposureTransformation : RGBTransformation {

    private const float EPSILON = 0.08f;
    private const float PARAMETER_SCALE = (1.0f / 32.0f);
    
    public const float MIN_PARAMETER = -16.0f;
    public const float MAX_PARAMETER = 16.0f;
    
    public ExposureTransformation(float parameter) {
        base();
    
        assert((parameter >= MIN_PARAMETER) && (parameter <= MAX_PARAMETER));

        if (parameter != 0.0f) {
        
            parameter *= PARAMETER_SCALE;
            if (parameter < 0.0f)
                parameter = 1.0f / (-parameter + 1.0f);
            else
                parameter += 1.0f;
            
            matrix_entries[0] = parameter;
            matrix_entries[5] = parameter;
            matrix_entries[10] = parameter;
            matrix_entries[3] = parameter * EPSILON;
            matrix_entries[7] = parameter * EPSILON;
            matrix_entries[11] = parameter * EPSILON;
            
            identity = false;
        }
    }
}

public class SaturationTransformation : RGBTransformation {

    private enum WeightKind { NTSC, LINEAR, FLAT }

    private const float NTSC_WEIGHT_RED = 0.299f;
    private const float NTSC_WEIGHT_GREEN = 0.587f;
    private const float NTSC_WEIGHT_BLUE = 0.114f;
    private const float LINEAR_WEIGHT_RED = 0.3086f;
    private const float LINEAR_WEIGHT_GREEN = 0.6094f;
    private const float LINEAR_WEIGHT_BLUE = 0.0820f;
    private const float FLAT_WEIGHT_RED = 0.333f;
    private const float FLAT_WEIGHT_GREEN = 0.333f;
    private const float FLAT_WEIGHT_BLUE = 0.333f;

    public const float MIN_PARAMETER = -16.0f;
    public const float MAX_PARAMETER = 16.0f;
    
    private WeightKind weight_kind = WeightKind.FLAT;
    
    public SaturationTransformation(float parameter) {
        base();

        assert((parameter >= MIN_PARAMETER) && (parameter <= MAX_PARAMETER));

        if (parameter != 0.0f) {
            float adjusted_param = parameter / MAX_PARAMETER;
            adjusted_param += 1.0f;

            float red_weight = 0.0f;
            float green_weight = 0.0f;
            float blue_weight = 0.0f;
            if (weight_kind == WeightKind.NTSC) {
                red_weight = NTSC_WEIGHT_RED;
                green_weight = NTSC_WEIGHT_GREEN;
                blue_weight = NTSC_WEIGHT_BLUE;
            } else if (weight_kind == WeightKind.LINEAR) {
                red_weight = LINEAR_WEIGHT_RED;
                green_weight = LINEAR_WEIGHT_GREEN;
                blue_weight = LINEAR_WEIGHT_BLUE;
            } else if (weight_kind == WeightKind.FLAT) {
                red_weight = FLAT_WEIGHT_RED;
                green_weight = FLAT_WEIGHT_GREEN;
                blue_weight = FLAT_WEIGHT_BLUE;
            } else {
                error("unrecognized weight kind.\n");
            }

            matrix_entries[0] = ((1.0f - adjusted_param) * red_weight) +
                adjusted_param;
            matrix_entries[1] = (1.0f - adjusted_param) * red_weight;
            matrix_entries[2] = (1.0f - adjusted_param) * red_weight;

            matrix_entries[4] = (1.0f - adjusted_param) * green_weight;
            matrix_entries[5] = ((1.0f - adjusted_param) * green_weight) +
                adjusted_param;
            matrix_entries[6] = (1.0f - adjusted_param) * green_weight;

            matrix_entries[8] = (1.0f - adjusted_param) * blue_weight;
            matrix_entries[9] = (1.0f - adjusted_param) * blue_weight;
            matrix_entries[10] = ((1.0f - adjusted_param) * blue_weight) +
                adjusted_param;
            
            identity = false;
        }
    }
}

public class TemperatureTransformation : RGBTransformation {
    private const float INTENSITY_FACTOR = 0.33f;
    public const float MIN_PARAMETER = -16.0f;
    public const float MAX_PARAMETER = 16.0f;

    public TemperatureTransformation(float parameter) {
        base();

        assert((parameter >= MIN_PARAMETER) && (parameter <= MAX_PARAMETER));
        
         if (parameter != 0.0f) {
             float adjusted_param = parameter / MAX_PARAMETER;
             adjusted_param *= INTENSITY_FACTOR;
             
             matrix_entries[11] -= adjusted_param;
             matrix_entries[7] += (adjusted_param / 2);
             matrix_entries[3] += (adjusted_param / 2);

             identity = false;
         }
    }
}

public class TintTransformation : RGBTransformation {
    private const float INTENSITY_FACTOR = 0.25f;
    public const float MIN_PARAMETER = -16.0f;
    public const float MAX_PARAMETER = 16.0f;

    public TintTransformation(float parameter) {
        base();

        assert((parameter >= MIN_PARAMETER) && (parameter <= MAX_PARAMETER));
        
         if (parameter != 0.0f) {
             float adjusted_param = parameter / MAX_PARAMETER;
             adjusted_param *= INTENSITY_FACTOR;
             
             matrix_entries[11] -= (adjusted_param / 2);
             matrix_entries[7] += adjusted_param;
             matrix_entries[3] -= (adjusted_param / 2);
 
             identity = false;             
         }
    }
}

public class RGBTransformationFactory {
    private static RGBTransformationFactory instance = null;
    
    public RGBTransformationFactory() {
    }
    
    public static RGBTransformationFactory get_instance() {
        if (instance == null)
            instance = new RGBTransformationFactory();

        return instance;
    }

    public RGBTransformation from_parameter(RGBTransformationKind kind,
        float parameter) {
        switch (kind) {
            case RGBTransformationKind.EXPOSURE:
                return new ExposureTransformation((float) parameter);
            case RGBTransformationKind.SATURATION:
                return new SaturationTransformation((float) parameter);
            case RGBTransformationKind.TINT:
                return new TintTransformation((float) parameter);
            case RGBTransformationKind.TEMPERATURE:
                return new TemperatureTransformation((float) parameter);
            default:
                error("unrecognized RGBTransformationKind enumeration value");
            break;
        }
        
        return new RGBTransformation();
    }
}

class RGBHistogram {
    private const uchar MARKED_BACKGROUND = 30;
    private const uchar MARKED_FOREGROUND = 210;
    private const uchar UNMARKED_BACKGROUND = 40;

    public const int GRAPHIC_WIDTH = 256;
    public const int GRAPHIC_HEIGHT = 100;

    private int[] red_counts = new int[256];
    private int[] green_counts = new int[256];
    private int[] blue_counts = new int[256];
    private int[] qualitative_red_counts = null;
    private int[] qualitative_green_counts = null;
    private int[] qualitative_blue_counts = null;
    private Gdk.Pixbuf graphic = null;

    public RGBHistogram(Gdk.Pixbuf pixbuf) {
        for (int i = 0; i < 256; i++)
            red_counts[i] = green_counts[i] = blue_counts[i] = 0;

        int sample_bytes = pixbuf.get_bits_per_sample() / 8;
        int pixel_bytes = sample_bytes * pixbuf.get_n_channels();
        int row_length_bytes = pixel_bytes * pixbuf.width;

        unowned uchar[] pixel_data = pixbuf.get_pixels();

        for (int y = 0; y < pixbuf.height; y++) {
            int row_start_offset = y * pixbuf.rowstride;

            int r_offset = row_start_offset;
            int g_offset = row_start_offset + sample_bytes;
            int b_offset = row_start_offset + sample_bytes + sample_bytes;

            while (b_offset < (row_start_offset + row_length_bytes)) {
                red_counts[pixel_data[r_offset]]++;
                green_counts[pixel_data[g_offset]]++;
                blue_counts[pixel_data[b_offset]]++;

                r_offset += pixel_bytes;
                g_offset += pixel_bytes;
                b_offset += pixel_bytes;
            }
        }
    }
    
    private int correct_snap_to_quantization(owned int[] buckets, int i) {
        assert(buckets.length == 256);
        assert((i >= 0) && (i <= 255));
        
        if (i == 0) {
            if (buckets[i] > 0)
                if (buckets[i + 1] > 0)
                    if (buckets[i] > (2 * buckets[i + 1]))
                       return buckets[i + 1];
        } else if (i == 255) {
            if (buckets[i] > 0)
                if (buckets[i - 1] > 0)
                    if (buckets[i] > (2 * buckets[i - 1]))
                       return buckets[i - 1];
        } else {
            if (buckets[i] > 0)
                if (buckets[i] > ((buckets[i - 1] + buckets[i + 1]) / 2))
                        return (buckets[i - 1] + buckets[i + 1]) / 2;
        }
        
        return buckets[i];
    }
    
    private int correct_snap_from_quantization(owned int[] buckets, int i) {
        assert(buckets.length == 256);
        assert((i >= 0) && (i <= 255));
        
        if (i == 0) {
            return buckets[i];
        } else if (i == 255) {
            return buckets[i];
        } else {
            if (buckets[i] == 0)
                if (buckets[i - 1] > 0)
                    if (buckets[i + 1] > 0)
                        return (buckets[i - 1] + buckets[i + 1]) / 2;
        }
        
        return buckets[i];
    }

    private void smooth_extrema(owned int[] count_data) {
        assert(count_data.length == 256);
        
        /* the blocks of code below are unrolled loops that replace values at the extrema
           (buckets 0-4 and 251-255, inclusive) of the histogram with a weighted
           average of their neighbors. This mitigates quantization and pooling artifacts */

        count_data[0] = (5 * count_data[0] + 3 * count_data[1] + 2 * count_data[2]) /
            10;
        count_data[1] = (3 * count_data[0] + 5 * count_data[1] + 3 * count_data[2] +
            2 * count_data[3]) / 13;
        count_data[2] = (2 * count_data[0] + 3 * count_data[1] + 5 * count_data[2] +
            3 * count_data[3] + 2 * count_data[4]) / 15;
        count_data[3] = (2 * count_data[1] + 3 * count_data[2] + 5 * count_data[3] +
            3 * count_data[4] + 2 * count_data[5]) / 15;
        count_data[4] = (2 * count_data[2] + 3 * count_data[3] + 5 * count_data[4] +
            3 * count_data[5] + 2 * count_data[6]) / 15;

        count_data[255] = (5 * count_data[255] + 3 * count_data[254] + 2 * count_data[253]) /
            10;
        count_data[254] = (3 * count_data[255] + 5 * count_data[254] + 3 * count_data[253] +
            2 * count_data[252]) / 13;
        count_data[253] = (2 * count_data[255] + 3 * count_data[254] + 5 * count_data[253] +
            3 * count_data[252] + 2 * count_data[251]) / 15;
        count_data[252] = (2 * count_data[254] + 3 * count_data[253] + 5 * count_data[252] +
            3 * count_data[251] + 2 * count_data[250]) / 15;
        count_data[251] = (2 * count_data[253] + 3 * count_data[252] + 5 * count_data[251] +
            3 * count_data[250] + 2 * count_data[249]) / 15;
    }
    
    private void prepare_qualitative_counts() {
        if ((qualitative_red_counts != null) && (qualitative_green_counts != null) &&
            (qualitative_blue_counts != null))
                return;

        qualitative_red_counts = new int[256];
        qualitative_green_counts = new int[256];
        qualitative_blue_counts = new int[256];

        int[] temp_red_counts = new int[256];
        int[] temp_green_counts = new int[256];
        int[] temp_blue_counts = new int[256];

        /* Remove snap-away-from-value quantization artifacts from the qualitative
           histogram. While these are indeed present in the underlying data as a
           consequence of sampling, transformation, and reconstruction, they lead
           to an unpleasant looking histogram, so we detect and eliminate them here */
        for (int i = 0; i < 256; i++) {
            qualitative_red_counts[i] =
                correct_snap_from_quantization(red_counts, i);
            qualitative_green_counts[i] =
                correct_snap_from_quantization(green_counts, i);
            qualitative_blue_counts[i] =
                correct_snap_from_quantization(blue_counts, i);
        }
        
        for (int i = 0; i < 256; i++) {
            temp_red_counts[i] = qualitative_red_counts[i];
            temp_green_counts[i] = qualitative_green_counts[i];
            temp_blue_counts[i] = qualitative_blue_counts[i];
        }

        /* Remove snap-to-value quantization artifacts from the qualitative
           histogram */
        for (int i = 0; i < 256; i++) {
            qualitative_red_counts[i] =
                correct_snap_to_quantization(temp_red_counts, i);
            qualitative_green_counts[i] =
                correct_snap_to_quantization(temp_green_counts, i);
            qualitative_blue_counts[i] =
                correct_snap_to_quantization(temp_blue_counts, i);
        }
        
        /* constrain the peaks in the qualitative histogram so that no peak can be more
           than 8 times higher than the mean height of the entire image */ 
        int mean_qual_count = 0;
        for (int i = 0; i < 256; i++) {
            mean_qual_count += (qualitative_red_counts[i] + qualitative_green_counts[i] +
                qualitative_blue_counts[i]);        
        }
        mean_qual_count /= (256 * 3);
        int constrained_max_qual_count = 8 * mean_qual_count;
        for (int i = 0; i < 256; i++) {
            if (qualitative_red_counts[i] > constrained_max_qual_count)
                qualitative_red_counts[i] = constrained_max_qual_count;

            if (qualitative_green_counts[i] > constrained_max_qual_count)
                qualitative_green_counts[i] = constrained_max_qual_count;

            if (qualitative_blue_counts[i] > constrained_max_qual_count)
                qualitative_blue_counts[i] = constrained_max_qual_count;
        }
        
        smooth_extrema(qualitative_red_counts);
        smooth_extrema(qualitative_green_counts);
        smooth_extrema(qualitative_blue_counts);
    }

    public Gdk.Pixbuf get_graphic() {
        if (graphic == null) {
            prepare_qualitative_counts();
            int max_count = 0;
            for (int i = 0; i < 256; i++) {
                if (qualitative_red_counts[i] > max_count)
                    max_count = qualitative_red_counts[i];
                if (qualitative_green_counts[i] > max_count)
                    max_count = qualitative_green_counts[i];
                if (qualitative_blue_counts[i] > max_count)
                    max_count = qualitative_blue_counts[i];
            }
            
            graphic = new Gdk.Pixbuf(Gdk.Colorspace.RGB, false, 8,
                GRAPHIC_WIDTH, GRAPHIC_HEIGHT);
            
            int rowstride = graphic.rowstride;
            int sample_bytes = graphic.get_bits_per_sample() / 8;
            int pixel_bytes = sample_bytes * graphic.get_n_channels();
            
            double scale_bar = 0.98 * ((double) GRAPHIC_HEIGHT) /
                ((double) max_count);

            unowned uchar[] pixel_data = graphic.get_pixels();

            for (int x = 0; x < 256; x++) {
                int red_bar_height = (int)(((double) qualitative_red_counts[x]) *
                    scale_bar);
                int green_bar_height = (int)(((double) qualitative_green_counts[x]) *
                    scale_bar);
                int blue_bar_height = (int)(((double) qualitative_blue_counts[x]) *
                    scale_bar);

                int max_bar_height = int.max(int.max(red_bar_height,
                    green_bar_height), blue_bar_height);

                int y = GRAPHIC_HEIGHT - 1;
                int pixel_index = (x * pixel_bytes) + (y * rowstride);
                for ( ; y >= (GRAPHIC_HEIGHT - max_bar_height); y--) {
                    pixel_data[pixel_index] = MARKED_BACKGROUND;
                    pixel_data[pixel_index + 1] = MARKED_BACKGROUND;
                    pixel_data[pixel_index + 2] = MARKED_BACKGROUND;
                    
                    if (y >= (GRAPHIC_HEIGHT - red_bar_height - 1))
                        pixel_data[pixel_index] = MARKED_FOREGROUND;
                    if (y >= (GRAPHIC_HEIGHT - green_bar_height - 1))
                        pixel_data[pixel_index + 1] = MARKED_FOREGROUND;
                    if (y >= (GRAPHIC_HEIGHT - blue_bar_height - 1))
                        pixel_data[pixel_index + 2] = MARKED_FOREGROUND;

                    pixel_index -= rowstride;
                }

                for ( ; y >= 0; y--) {
                    pixel_data[pixel_index] = UNMARKED_BACKGROUND;
                    pixel_data[pixel_index + 1] = UNMARKED_BACKGROUND;
                    pixel_data[pixel_index + 2] = UNMARKED_BACKGROUND;

                    pixel_index -= rowstride;
                }
            }
        }

        return graphic;
    }
}

public class IntensityHistogram {
    private int[] counts = new int[256];
    private float[] probabilities = new float[256];
    private float[] cumulative_probabilities = new float[256];

    public IntensityHistogram(Gdk.Pixbuf pixbuf) {
        for (int y = 0; y < pixbuf.height; y++) {
            for (int x = 0; x < pixbuf.width; x++) {
                RGBAnalyticPixel pix_rgb = RGBAnalyticPixel.get_pixbuf_pixel(
                    pixbuf, x, y);
                HSVAnalyticPixel pix_hsi = HSVAnalyticPixel.from_rgb(pix_rgb);
                int quantized_light_value = (int)(pix_hsi.light_value * 255.0f);
                counts[quantized_light_value]++;
            }
        }

        double pixel_count = (double)(pixbuf.width * pixbuf.height);
        float accumulator = 0.0f;
        for (int i = 0; i < 256; i++) {
            probabilities[i] = (float)(((double) counts[i]) / pixel_count);
            accumulator += probabilities[i];
            cumulative_probabilities[i] = accumulator;
        }
    }

    public float get_cumulative_probability(int level) {
        assert((level >= 0) && (level < 256));
        return cumulative_probabilities[level];
    }
}

public abstract class IntensityTransformation {

    public virtual HSVAnalyticPixel transform_pixel(HSVAnalyticPixel pixel) {
        return pixel;
    }

    public static void transform_pixbuf(IntensityTransformation transform,
        Gdk.Pixbuf pixbuf) {
        for (int j = 0; j < pixbuf.height; j++) {
            for (int i = 0; i < pixbuf.width; i++) {
            
                RGBAnalyticPixel pixel_ij_rgb =
                    RGBAnalyticPixel.get_pixbuf_pixel(pixbuf, i, j);
                    
                HSVAnalyticPixel pixel_ij =
                    HSVAnalyticPixel.from_rgb(pixel_ij_rgb);

                HSVAnalyticPixel pixel_ij_transformed =
                    transform.transform_pixel(pixel_ij);
                
                RGBAnalyticPixel pixel_ij_transformed_rgb =
                    pixel_ij_transformed.to_rgb();
                
                RGBAnalyticPixel.set_pixbuf_pixel(pixbuf,
                    pixel_ij_transformed_rgb, i, j);
            }
        }
    }
    
    public abstract string to_string();
}

public class NormalizationTransformation : IntensityTransformation {
    private float[] remap_table = null;
    private const float LOW_DISCARD_MASS = 0.02f;
    private const float HIGH_DISCARD_MASS = 0.02f;
    private const float FIXED_SATURATION_MULTIPLIER = 1.0f;

    private int low_kink;
    private int high_kink;

    public NormalizationTransformation(IntensityHistogram histogram) {
        remap_table = new float[256];

        float LOW_KINK_MASS = LOW_DISCARD_MASS;
        low_kink = 0;
        while (histogram.get_cumulative_probability(low_kink) < LOW_KINK_MASS)
            low_kink++;
        
        float HIGH_KINK_MASS = 1.0f - HIGH_DISCARD_MASS;
        high_kink = 255;
        while (histogram.get_cumulative_probability(high_kink) > HIGH_KINK_MASS)
            high_kink--;

        build_remap_table();
    }
    
    public NormalizationTransformation.from_string(string encoded_transformation) {
        encoded_transformation.canon("0123456789. ", ' ');
        encoded_transformation.chug();
        encoded_transformation.chomp();

        int num_captured = encoded_transformation.scanf("%d %d", &low_kink,
            &high_kink);

        assert(num_captured == 2);
        
        build_remap_table();
    }
    
    private void build_remap_table() {
        if (remap_table == null)
            remap_table = new float[256];

        float low_kink_f = ((float) low_kink) / 255.0f;
        float high_kink_f = ((float) high_kink) / 255.0f;

        float slope = 1.0f / (high_kink_f - low_kink_f);
        float intercept = -(low_kink_f / (high_kink_f - low_kink_f));
        
        int i = 0;
        for ( ; i <= low_kink; i++)
            remap_table[i] = 0.0f;
        
        for ( ; i < high_kink; i++)
            remap_table[i] = slope * (((float) i) / 255.0f) + intercept;
        
        for ( ; i < 256; i++)
            remap_table[i] = 1.0f;
    }

    public override HSVAnalyticPixel transform_pixel(HSVAnalyticPixel pixel) {
        int remap_index = (int)(pixel.light_value * 255.0f);

        HSVAnalyticPixel result = pixel;
        result.light_value = remap_table[remap_index];
        result.saturation *= FIXED_SATURATION_MULTIPLIER;

        result.saturation = result.saturation.clamp(0.0f, 1.0f);
        result.light_value = result.light_value.clamp(0.0f, 1.0f);

        return result;
    }

    public override string to_string() {
        return "{ %d, %d }".printf(low_kink, high_kink);
    }
}

public class EnhancementFactory {
    private const int CURRENT_VERSION = 1;
    private const int MIN_SUPPORTED_VERSION = 1;
    
    public static int get_current_version() {
        return CURRENT_VERSION;
    }
    
    public static bool is_encoding_version_supported(int encoding_version) {
        if (encoding_version < MIN_SUPPORTED_VERSION)
            return false;
        
        if (encoding_version > CURRENT_VERSION)
            return false;
        
        return true;
    }
    
    public static IntensityTransformation? create_from_encoding(int encoding_version,
        string encoded_transformation) {
        
        switch (encoding_version) {
            case 1:
                return new NormalizationTransformation.from_string(encoded_transformation);

            default:
                warning("enhancement factory: unsupported transformation encoding version");
                return null;
        }
    }
    
    public static IntensityTransformation create_current(Gdk.Pixbuf target) {
        IntensityHistogram histogram = new IntensityHistogram(target);
        return new NormalizationTransformation(histogram);
    }
}

