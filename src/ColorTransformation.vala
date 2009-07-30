/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */
 
public struct AnalyticPixel {
    public float red;
    public float green;
    public float blue;
    
    public AnalyticPixel() {
        red = 0.0f;
        green = 0.0f;
        blue = 0.0f;
    }
    
    public AnalyticPixel.from_components(float red, float green,
        float blue) {
        this.red = red.clamp(0.0f, 1.0f);
        this.green = green.clamp(0.0f, 1.0f);
        this.blue = blue.clamp(0.0f, 1.0f);
    }
    
    public AnalyticPixel.from_quantized_components(uchar red_quantized,
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
    
    public static AnalyticPixel get_pixbuf_pixel(owned Gdk.Pixbuf pixbuf,
        int x, int y) {
        assert((x >= 0) && (x < pixbuf.width));
        assert((y >= 0) && (y < pixbuf.height));
        
        int px_start_byte_offset = (y * pixbuf.rowstride) + (x *
            pixbuf.n_channels);
        
        unowned uchar[] pixel_data = pixbuf.get_pixels();
        
        return AnalyticPixel.from_quantized_components(
            pixel_data[px_start_byte_offset],
            pixel_data[px_start_byte_offset + 1],
            pixel_data[px_start_byte_offset + 2]);
    }
    
    public static void set_pixbuf_pixel(owned Gdk.Pixbuf pixbuf,
        AnalyticPixel pixel, int x, int y) {
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

public enum ColorTransformationKind {
    EXPOSURE,
    SATURATION,
    TINT,
    TEMPERATURE
}

public struct ColorTransformationInstance {
    public ColorTransformationKind kind;
    public float parameter;
}

public class ColorTransformation {
    /* matrix entries are stored in row-major; by default, the matrix formed
       by matrix_entries is the 4x4 identity matrix */
    protected float[] matrix_entries = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f };
    
    protected bool identity = true;

    public ColorTransformation() {
    }
    
    public bool is_identity() {
        return identity;
    }
    
    public AnalyticPixel transform_pixel(AnalyticPixel pixel) {
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
        
        return AnalyticPixel.from_components(red_out, green_out, blue_out);
            
    }
    
    public ColorTransformation compose_against(ColorTransformation transform) {
        ColorTransformation result = new ColorTransformation();
        
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

    public static void transform_pixbuf(ColorTransformation transform,
        owned Gdk.Pixbuf pixbuf) {
        for (int j = 0; j < pixbuf.height; j++) {
            for (int i = 0; i < pixbuf.width; i++) {
            
                AnalyticPixel pixel_ij =
                    AnalyticPixel.get_pixbuf_pixel(pixbuf, i, j);

                AnalyticPixel pixel_ij_transformed =
                    transform.transform_pixel(pixel_ij);
                
                AnalyticPixel.set_pixbuf_pixel(pixbuf, pixel_ij_transformed,
                    i, j);
            }
        }
    }
    
    public static void transform_existing_pixbuf(ColorTransformation transform,
        owned Gdk.Pixbuf in_pixbuf, owned Gdk.Pixbuf out_pixbuf) {
        assert((in_pixbuf.width == out_pixbuf.width) && (in_pixbuf.height ==
            out_pixbuf.height));
        for (int j = 0; j < in_pixbuf.height; j++) {
            for (int i = 0; i < in_pixbuf.width; i++) {
            
                AnalyticPixel pixel_ij =
                    AnalyticPixel.get_pixbuf_pixel(in_pixbuf, i, j);

                AnalyticPixel pixel_ij_transformed =
                    transform.transform_pixel(pixel_ij);
                
                AnalyticPixel.set_pixbuf_pixel(out_pixbuf, pixel_ij_transformed,
                    i, j);
            }
        }
    }
}
 
public class ExposureTransformation : ColorTransformation {

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

public class SaturationTransformation : ColorTransformation {

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

public class TemperatureTransformation : ColorTransformation {
    private const float INTENSITY_FACTOR = 0.33;
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

public class TintTransformation : ColorTransformation {
    private const float INTENSITY_FACTOR = 0.25;
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

public class ColorTransformationFactory {
    private static ColorTransformationFactory instance = null;
    
    public ColorTransformationFactory() {
    }
    
    public static ColorTransformationFactory get_instance() {
        if (instance == null)
            instance = new ColorTransformationFactory();

        return instance;
    }

    public ColorTransformation from_parameter(ColorTransformationKind kind,
        float parameter) {
        switch (kind) {
            case ColorTransformationKind.EXPOSURE:
                return new ExposureTransformation((float) parameter);
            case ColorTransformationKind.SATURATION:
                return new SaturationTransformation((float) parameter);
            case ColorTransformationKind.TINT:
                return new TintTransformation((float) parameter);
            case ColorTransformationKind.TEMPERATURE:
                return new TemperatureTransformation((float) parameter);
            default:
                error("unrecognized ColorTransformationKind enumeration value");
            break;
        }
        
        return new ColorTransformation();
    }
}

