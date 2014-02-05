/* Copyright 2009-2014 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

public struct RGBAnalyticPixel {
    public float red;
    public float green;
    public float blue;

    private const float INV_255 = 1.0f / 255.0f;

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
        this.red = ((float) red_quantized) * INV_255;
        this.green = ((float) green_quantized) * INV_255;
        this.blue = ((float) blue_quantized) * INV_255;
    }

    public RGBAnalyticPixel.from_hsv(HSVAnalyticPixel hsv_pixel) {
        RGBAnalyticPixel from_hsv = hsv_pixel.to_rgb();
        red = from_hsv.red;
        green = from_hsv.green;
        blue = from_hsv.blue;
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

    public bool equals(RGBAnalyticPixel? rhs) {
        return ((red == rhs.red) && (green == rhs.green) && (blue == rhs.blue));
    }

    public uint hash_code() {
        return (((uint)(red * 255.0f)) << 16) + (((uint)(green * 255.0f)) << 8) +
            ((uint)(blue * 255.0f));
    }

    public HSVAnalyticPixel to_hsv() {
        return HSVAnalyticPixel.from_rgb(this);
    }
}

public struct HSVAnalyticPixel {
    public float hue;
    public float saturation;
    public float light_value;
    
    private const float INV_255 = 1.0f / 255.0f;

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

    public HSVAnalyticPixel.from_quantized_components(uchar hue_quantized,
        uchar saturation_quantized, uchar light_value_quantized) {
        this.hue = ((float) hue_quantized) * INV_255;
        this.saturation = ((float) saturation_quantized) * INV_255;
        this.light_value = ((float) light_value_quantized) * INV_255;
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
            }
        }

        return result;
    }

    public bool equals(ref HSVAnalyticPixel rhs) {
        return ((hue == rhs.hue) && (saturation == rhs.saturation) &&
                (light_value == rhs.light_value));
    }

    public uint hash_code() {
        return (((uint)(hue * 255.0f)) << 16) + (((uint)(saturation * 255.0f)) << 8) +
            ((uint)(light_value * 255.0f));
    }
}

public enum CompositionMode {
    NONE,
    RGB_MATRIX
}

public enum PixelFormat {
    RGB,
    HSV
}

public enum PixelTransformationType {
    TONE_EXPANSION,
    SHADOWS,
    HIGHLIGHTS,
    TEMPERATURE,
    TINT,
    SATURATION,
    EXPOSURE
}

public class PixelTransformationBundle {
    private static PixelTransformationBundle? copied_color_adjustments = null;
    
    private Gee.HashMap<int, PixelTransformation> map = new Gee.HashMap<int, PixelTransformation>(
        Gee.Functions.get_hash_func_for(typeof(int)), Gee.Functions.get_equal_func_for(typeof(int)));
    
    public PixelTransformationBundle() {
    }
    
    public static PixelTransformationBundle? get_copied_color_adjustments() {
        return copied_color_adjustments;
    }
    
    public static void set_copied_color_adjustments(PixelTransformationBundle adjustments) {
        copied_color_adjustments = adjustments;
    }
    
    public static bool has_copied_color_adjustments() {
        return copied_color_adjustments != null;
    }
    
    public void set(PixelTransformation transformation) {
        map.set((int) transformation.get_transformation_type(), transformation);
    }
    
    public void set_to_identity() {
        set(new ExpansionTransformation.from_extrema(0, 255));
        set(new ShadowDetailTransformation(0.0f));
        set(new HighlightDetailTransformation(0.0f));
        set(new TemperatureTransformation(0.0f));
        set(new TintTransformation(0.0f));
        set(new SaturationTransformation(0.0f));
        set(new ExposureTransformation(0.0f));
    }
    
    public void load(KeyValueMap store) {
        string expansion_params_encoded = store.get_string("expansion", "-");
        if (expansion_params_encoded == "-")
            set(new ExpansionTransformation.from_extrema(0, 255));
        else
            set(new ExpansionTransformation.from_string(expansion_params_encoded));
        
        set(new ShadowDetailTransformation(store.get_float("shadows", 0.0f)));
        set(new HighlightDetailTransformation(store.get_float("highlights", 0.0f)));
        set(new TemperatureTransformation(store.get_float("temperature", 0.0f)));
        set(new TintTransformation(store.get_float("tint", 0.0f)));
        set(new SaturationTransformation(store.get_float("saturation", 0.0f)));
        set(new ExposureTransformation(store.get_float("exposure", 0.0f)));
    }
    
    public KeyValueMap save(string group) {
        KeyValueMap store = new KeyValueMap(group);
        
        ExpansionTransformation? new_expansion_trans =
            (ExpansionTransformation) get_transformation(PixelTransformationType.TONE_EXPANSION);
        assert(new_expansion_trans != null);
        store.set_string("expansion", new_expansion_trans.to_string());
        
        ShadowDetailTransformation? new_shadows_trans =
            (ShadowDetailTransformation) get_transformation(PixelTransformationType.SHADOWS);
        assert(new_shadows_trans != null);
        store.set_float("shadows", new_shadows_trans.get_parameter());

        HighlightDetailTransformation? new_highlight_trans =
            (HighlightDetailTransformation) get_transformation(PixelTransformationType.HIGHLIGHTS);
        assert(new_highlight_trans != null);
        store.set_float("highlights", new_highlight_trans.get_parameter());
        
        TemperatureTransformation? new_temp_trans =
            (TemperatureTransformation) get_transformation(PixelTransformationType.TEMPERATURE);
        assert(new_temp_trans != null);
        store.set_float("temperature", new_temp_trans.get_parameter());

        TintTransformation? new_tint_trans =
            (TintTransformation) get_transformation(PixelTransformationType.TINT);
        assert(new_tint_trans != null);
        store.set_float("tint", new_tint_trans.get_parameter());

        SaturationTransformation? new_sat_trans =
            (SaturationTransformation) get_transformation(PixelTransformationType.SATURATION);
        assert(new_sat_trans != null);
        store.set_float("saturation", new_sat_trans.get_parameter());

        ExposureTransformation? new_exposure_trans =
            (ExposureTransformation) get_transformation(PixelTransformationType.EXPOSURE);
        assert(new_exposure_trans != null);
        store.set_float("exposure", new_exposure_trans.get_parameter());
        
        return store;
    }
    
    public int get_count() {
        return map.size;
    }
    
    public PixelTransformation? get_transformation(PixelTransformationType type) {
        return map.get((int) type);
    }
    
    public Gee.Iterable<PixelTransformation> get_transformations() {
        return map.values;
    }
    
    public bool is_identity() {
        foreach (PixelTransformation adjustment in get_transformations()) {
            if (!adjustment.is_identity())
                return false;
        }
        
        return true;
    }
    
    public PixelTransformer generate_transformer() {
        PixelTransformer transformer = new PixelTransformer();
        foreach (PixelTransformation transformation in get_transformations())
            transformer.attach_transformation(transformation);
        
        return transformer;
    }
    
    public PixelTransformationBundle copy() {
        PixelTransformationBundle bundle = new PixelTransformationBundle();
        foreach (PixelTransformation transformation in get_transformations())
            bundle.set(transformation);
        
        return bundle;
    }
}

public abstract class PixelTransformation {
    private PixelTransformationType type;
    
    public PixelTransformation(PixelTransformationType type) {
        this.type = type;
    }
    
    public PixelTransformationType get_transformation_type() {
        return type;
    }
    
    public abstract PixelFormat get_preferred_format();

    public virtual CompositionMode get_composition_mode() {
        return CompositionMode.NONE;
    }

    public virtual void compose_with(PixelTransformation other) {
        error("PixelTransformation: compose_with( ): this type of pixel " +
            "transformation doesn't support composition.");
    }

    public virtual bool is_identity() {
        return true;
    }

    public virtual HSVAnalyticPixel transform_pixel_hsv(HSVAnalyticPixel p) {
        return p;
    }

    public virtual RGBAnalyticPixel transform_pixel_rgb(RGBAnalyticPixel p) {
        return p;
    }

    public virtual string to_string() {
        return "PixelTransformation";
    }
    
    public abstract PixelTransformation copy();
}

public class RGBTransformation : PixelTransformation {
    /* matrix entries are stored in row-major order; by default, the matrix formed
       by matrix_entries is the 4x4 identity matrix */
    protected float[] matrix_entries;
    
    protected const int MATRIX_SIZE = 16;

    protected bool identity = true;
    
    public RGBTransformation(PixelTransformationType type) {
        base(type);
        
        // Can't initialize these in their member declarations because of a valac bug that
        // I've been unable to produce a minimal test case for to report (JN).  May be 
        // related to this bug:
        // https://bugzilla.gnome.org/show_bug.cgi?id=570821
        matrix_entries = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f };
    }

    public override PixelFormat get_preferred_format() {
        return PixelFormat.RGB;
    }

    public override CompositionMode get_composition_mode() {
        return CompositionMode.RGB_MATRIX;
    }

    public override void compose_with(PixelTransformation other) {
        if (other.get_composition_mode() != CompositionMode.RGB_MATRIX)
            error("RGBTransformation: compose_with( ): 'other' transformation " +
                "does not support RGB_MATRIX composition mode");

        RGBTransformation transform = (RGBTransformation) other;

        float[] result_matrix_entries = new float[16];

        /* row 0 */
        result_matrix_entries[0] =
            (transform.matrix_entries[0] * matrix_entries[0]) +
            (transform.matrix_entries[1] * matrix_entries[4]) +
            (transform.matrix_entries[2] * matrix_entries[8]) +
            (transform.matrix_entries[3] * matrix_entries[12]);

        result_matrix_entries[1] =
            (transform.matrix_entries[0] * matrix_entries[1]) +
            (transform.matrix_entries[1] * matrix_entries[5]) +
            (transform.matrix_entries[2] * matrix_entries[9]) +
            (transform.matrix_entries[3] * matrix_entries[13]);

        result_matrix_entries[2] =
            (transform.matrix_entries[0] * matrix_entries[2]) +
            (transform.matrix_entries[1] * matrix_entries[6]) +
            (transform.matrix_entries[2] * matrix_entries[10]) +
            (transform.matrix_entries[3] * matrix_entries[14]);

        result_matrix_entries[3] =
            (transform.matrix_entries[0] * matrix_entries[3]) +
            (transform.matrix_entries[1] * matrix_entries[7]) +
            (transform.matrix_entries[2] * matrix_entries[11]) +
            (transform.matrix_entries[3] * matrix_entries[15]);

        /* row 1 */
        result_matrix_entries[4] =
            (transform.matrix_entries[4] * matrix_entries[0]) +
            (transform.matrix_entries[5] * matrix_entries[4]) +
            (transform.matrix_entries[6] * matrix_entries[8]) +
            (transform.matrix_entries[7] * matrix_entries[12]);

        result_matrix_entries[5] =
            (transform.matrix_entries[4] * matrix_entries[1]) +
            (transform.matrix_entries[5] * matrix_entries[5]) +
            (transform.matrix_entries[6] * matrix_entries[9]) +
            (transform.matrix_entries[7] * matrix_entries[13]);

        result_matrix_entries[6] =
            (transform.matrix_entries[4] * matrix_entries[2]) +
            (transform.matrix_entries[5] * matrix_entries[6]) +
            (transform.matrix_entries[6] * matrix_entries[10]) +
            (transform.matrix_entries[7] * matrix_entries[14]);

        result_matrix_entries[7] =
            (transform.matrix_entries[4] * matrix_entries[3]) +
            (transform.matrix_entries[5] * matrix_entries[7]) +
            (transform.matrix_entries[6] * matrix_entries[11]) +
            (transform.matrix_entries[7] * matrix_entries[15]);

        /* row 2 */
        result_matrix_entries[8] =
            (transform.matrix_entries[8] * matrix_entries[0]) +
            (transform.matrix_entries[9] * matrix_entries[4]) +
            (transform.matrix_entries[10] * matrix_entries[8]) +
            (transform.matrix_entries[11] * matrix_entries[12]);

        result_matrix_entries[9] =
            (transform.matrix_entries[8] * matrix_entries[1]) +
            (transform.matrix_entries[9] * matrix_entries[5]) +
            (transform.matrix_entries[10] * matrix_entries[9]) +
            (transform.matrix_entries[11] * matrix_entries[13]);

        result_matrix_entries[10] =
            (transform.matrix_entries[8] * matrix_entries[2]) +
            (transform.matrix_entries[9] * matrix_entries[6]) +
            (transform.matrix_entries[10] * matrix_entries[10]) +
            (transform.matrix_entries[11] * matrix_entries[14]);

        result_matrix_entries[11] =
            (transform.matrix_entries[8] * matrix_entries[3]) +
            (transform.matrix_entries[9] * matrix_entries[7]) +
            (transform.matrix_entries[10] * matrix_entries[11]) +
            (transform.matrix_entries[11] * matrix_entries[15]);

        /* row 3 */
        result_matrix_entries[12] =
            (transform.matrix_entries[12] * matrix_entries[0]) +
            (transform.matrix_entries[13] * matrix_entries[4]) +
            (transform.matrix_entries[14] * matrix_entries[8]) +
            (transform.matrix_entries[15] * matrix_entries[12]);

        result_matrix_entries[13] =
            (transform.matrix_entries[12] * matrix_entries[1]) +
            (transform.matrix_entries[13] * matrix_entries[5]) +
            (transform.matrix_entries[14] * matrix_entries[9]) +
            (transform.matrix_entries[15] * matrix_entries[13]);

        result_matrix_entries[14] =
            (transform.matrix_entries[12] * matrix_entries[2]) +
            (transform.matrix_entries[13] * matrix_entries[6]) +
            (transform.matrix_entries[14] * matrix_entries[10]) +
            (transform.matrix_entries[15] * matrix_entries[14]);

        result_matrix_entries[15] =
            (transform.matrix_entries[12] * matrix_entries[3]) +
            (transform.matrix_entries[13] * matrix_entries[7]) +
            (transform.matrix_entries[14] * matrix_entries[11]) +
            (transform.matrix_entries[15] * matrix_entries[15]);

        for (int i = 0; i < MATRIX_SIZE; i++)
            matrix_entries[i] = result_matrix_entries[i];

        identity = (identity && transform.identity);
    }

    public override HSVAnalyticPixel transform_pixel_hsv(HSVAnalyticPixel p) {
        return (transform_pixel_rgb(p.to_rgb())).to_hsv();
    }

    public override RGBAnalyticPixel transform_pixel_rgb(RGBAnalyticPixel p) {
        float red_out = (p.red * matrix_entries[0]) +
            (p.green * matrix_entries[1]) +
            (p.blue * matrix_entries[2]) +
            matrix_entries[3];
        red_out = red_out.clamp(0.0f, 1.0f);

        float green_out = (p.red * matrix_entries[4]) +
            (p.green * matrix_entries[5]) +
            (p.blue * matrix_entries[6]) +
            matrix_entries[7];
        green_out = green_out.clamp(0.0f, 1.0f);

        float blue_out = (p.red * matrix_entries[8]) +
            (p.green * matrix_entries[9]) +
            (p.blue * matrix_entries[10]) +
            matrix_entries[11];
        blue_out = blue_out.clamp(0.0f, 1.0f);
        
        return RGBAnalyticPixel.from_components(red_out, green_out, blue_out);
    }

    public override bool is_identity() {
        return identity;
    }
    
    public override PixelTransformation copy() {
        RGBTransformation result = new RGBTransformation(get_transformation_type());

        for (int i = 0; i < MATRIX_SIZE; i++) {
            result.matrix_entries[i] = matrix_entries[i];
        }

        return result;
    }
}

public abstract class HSVTransformation : PixelTransformation {
    public HSVTransformation(PixelTransformationType type) {
        base(type);
    }
    
    public override PixelFormat get_preferred_format() {
        return PixelFormat.HSV;
    }

    public override RGBAnalyticPixel transform_pixel_rgb(RGBAnalyticPixel p) {
        return (transform_pixel_hsv(p.to_hsv())).to_rgb();
    }
}

public class TintTransformation : RGBTransformation {
    private const float INTENSITY_FACTOR = 0.25f;
    public const float MIN_PARAMETER = -16.0f;
    public const float MAX_PARAMETER = 16.0f;
    
    private float parameter;

    public TintTransformation(float client_param) {
        base(PixelTransformationType.TINT);
        
        parameter = client_param.clamp(MIN_PARAMETER, MAX_PARAMETER);

         if (parameter != 0.0f) {
             float adjusted_param = parameter / MAX_PARAMETER;
             adjusted_param *= INTENSITY_FACTOR;
             
             matrix_entries[11] -= (adjusted_param / 2);
             matrix_entries[7] += adjusted_param;
             matrix_entries[3] -= (adjusted_param / 2);
 
             identity = false;
         }
    }

    public float get_parameter() {
        return parameter;
    }
}

public class TemperatureTransformation : RGBTransformation {
    private const float INTENSITY_FACTOR = 0.33f;
    public const float MIN_PARAMETER = -16.0f;
    public const float MAX_PARAMETER = 16.0f;
    
    private float parameter;

    public TemperatureTransformation(float client_parameter) {
        base(PixelTransformationType.TEMPERATURE);
        
        parameter = client_parameter.clamp(MIN_PARAMETER, MAX_PARAMETER);
        
         if (parameter != 0.0f) {
             float adjusted_param = parameter / MAX_PARAMETER;
             adjusted_param *= INTENSITY_FACTOR;
             
             matrix_entries[11] -= adjusted_param;
             matrix_entries[7] += (adjusted_param / 2);
             matrix_entries[3] += (adjusted_param / 2);

             identity = false;
         }
    }

    public float get_parameter() {
        return parameter;
    }
}

public class SaturationTransformation : RGBTransformation {
    public const float MIN_PARAMETER = -16.0f;
    public const float MAX_PARAMETER = 16.0f;
    
    private float parameter;

    public SaturationTransformation(float client_parameter) {
        base(PixelTransformationType.SATURATION);
        
        parameter = client_parameter.clamp(MIN_PARAMETER, MAX_PARAMETER);

        if (parameter != 0.0f) {
            float adjusted_param = parameter / MAX_PARAMETER;
            adjusted_param += 1.0f;

            float one_third = 0.3333333f;

            matrix_entries[0] = ((1.0f - adjusted_param) * one_third) +
                adjusted_param;
            matrix_entries[1] = (1.0f - adjusted_param) * one_third;
            matrix_entries[2] = (1.0f - adjusted_param) * one_third;

            matrix_entries[4] = (1.0f - adjusted_param) * one_third;
            matrix_entries[5] = ((1.0f - adjusted_param) * one_third) +
                adjusted_param;
            matrix_entries[6] = (1.0f - adjusted_param) * one_third;

            matrix_entries[8] = (1.0f - adjusted_param) * one_third;
            matrix_entries[9] = (1.0f - adjusted_param) * one_third;
            matrix_entries[10] = ((1.0f - adjusted_param) * one_third) +
                adjusted_param;

            identity = false;
        }
    }

    public float get_parameter() {
        return parameter;
    }
}

public class ExposureTransformation : RGBTransformation {
    public const float MIN_PARAMETER = -16.0f;
    public const float MAX_PARAMETER = 16.0f;

    float parameter;

    public ExposureTransformation(float client_parameter) {
        base(PixelTransformationType.EXPOSURE);
        
        parameter = client_parameter.clamp(MIN_PARAMETER, MAX_PARAMETER);

        if (parameter != 0.0f) {

            float adjusted_param = ((parameter + 16.0f) / 32.0f) + 0.5f;

            matrix_entries[0] = adjusted_param;
            matrix_entries[5] = adjusted_param;
            matrix_entries[10] = adjusted_param;

            identity = false;
        }
    }

    public float get_parameter() {
        return parameter;
    }
}

public class PixelTransformer {
    private Gee.ArrayList<PixelTransformation> transformations =
        new Gee.ArrayList<PixelTransformation>();
    private PixelTransformation[] optimized_transformations = null;
    private int optimized_slots_used = 0;
    
    public PixelTransformer() {
    }
    
    public PixelTransformer copy() {
        PixelTransformer clone = new PixelTransformer();
        
        foreach (PixelTransformation transformation in transformations)
            clone.transformations.add(transformation);
        
        return clone;
    }
    
    private void build_optimized_transformations() {
        optimized_transformations = new PixelTransformation[transformations.size];

        PixelTransformation pre_trans = null;
        optimized_slots_used = 0;
        for (int i = 0; i < transformations.size; i++) {
            PixelTransformation trans = transformations.get(i);

            if (trans.is_identity())
                continue;

            PixelTransformation this_trans = null;
            if (trans.get_composition_mode() == CompositionMode.NONE)
                this_trans = trans;
            else
                this_trans = trans.copy();

            if ((pre_trans != null) && (this_trans.get_composition_mode() != CompositionMode.NONE)
                && (this_trans.get_composition_mode() == pre_trans.get_composition_mode())) {
                    pre_trans.compose_with(this_trans);
            } else {
                    optimized_transformations[optimized_slots_used++] = this_trans;
                    pre_trans = this_trans;
            }
        }
    }
    
    private RGBAnalyticPixel apply_transformations(RGBAnalyticPixel p) {
        PixelFormat current_format = PixelFormat.RGB;
        RGBAnalyticPixel p_rgb = p;
        HSVAnalyticPixel p_hsv = HSVAnalyticPixel();

        for (int i = 0; i < optimized_slots_used; i++) {
            PixelTransformation trans = optimized_transformations[i];
            if (trans.get_preferred_format() == PixelFormat.RGB) {
                if (current_format == PixelFormat.HSV) {
                    p_rgb = p_hsv.to_rgb();
                    current_format = PixelFormat.RGB;
                }
                p_rgb = trans.transform_pixel_rgb(p_rgb);
            } else {
                if (current_format == PixelFormat.RGB) {
                    p_hsv = p_rgb.to_hsv();
                    current_format = PixelFormat.HSV;
                }
                p_hsv = trans.transform_pixel_hsv(p_hsv);
            }
        }

        if (current_format == PixelFormat.HSV)
            p_rgb = p_hsv.to_rgb();

        return p_rgb;
    }

    /* NOTE: this method allows the same transformation to be added multiple
             times. There's nothing wrong with this behavior as of today,
             but it may be a policy that we want to change in the future */
    public void attach_transformation(PixelTransformation trans) {
        transformations.add(trans);
        optimized_transformations = null;
    }

    /* NOTE: if a transformation has been added multiple times, only the first
             instance of it will be removed */
    public void detach_transformation(PixelTransformation victim) {
        transformations.remove(victim);
        optimized_transformations = null;
    }

    /* NOTE: if a transformation has been added multiple times, only the first
             instance of it will be replaced with 'new' */
    public void replace_transformation(PixelTransformation old_trans,
        PixelTransformation new_trans) {
        for (int i = 0; i < transformations.size; i++) {
            if (transformations.get(i) == old_trans) {
                transformations.set(i, new_trans);

                optimized_transformations = null;
                return;
            }
        }
        error("PixelTransformer: replace_transformation( ): old_trans is not present in " +
            "transformation collection");
    }

    public void transform_pixbuf(Gdk.Pixbuf pixbuf, Cancellable? cancellable = null) {
        transform_to_other_pixbuf(pixbuf, pixbuf, cancellable);
    }

    public void transform_from_fp(ref float[] fp_pixel_cache, Gdk.Pixbuf dest) {
        if (optimized_transformations == null)
            build_optimized_transformations();

        int dest_width = dest.get_width();
        int dest_height = dest.get_height();
        int dest_num_channels = dest.get_n_channels();
        int dest_rowstride = dest.get_rowstride();
        unowned uchar[] dest_pixels = dest.get_pixels();
        
        int cache_pixel_ticker = 0;

        for (int j = 0; j < dest_height; j++) {
            int row_start_index = j * dest_rowstride;
            int row_end_index = row_start_index + (dest_width * dest_num_channels);
            for (int i = row_start_index; i < row_end_index; i += dest_num_channels) {
                RGBAnalyticPixel pixel = RGBAnalyticPixel.from_components(
                    fp_pixel_cache[cache_pixel_ticker],
                    fp_pixel_cache[cache_pixel_ticker + 1],
                    fp_pixel_cache[cache_pixel_ticker + 2]);

                cache_pixel_ticker += 3;

                pixel = apply_transformations(pixel);

                dest_pixels[i] = (uchar) (pixel.red * 255.0f);
                dest_pixels[i + 1] = (uchar) (pixel.green * 255.0f);
                dest_pixels[i + 2] = (uchar) (pixel.blue * 255.0f);
            }
        }
    }

    public void transform_to_other_pixbuf(Gdk.Pixbuf source, Gdk.Pixbuf dest,
        Cancellable? cancellable = null) {
        if (source.width != dest.width)
            error("PixelTransformer: source and destination pixbufs must have the same width");

        if (source.height != dest.height)
            error("PixelTransformer: source and destination pixbufs must have the same height");

        if (source.n_channels != dest.n_channels)
            error("PixelTransformer: source and destination pixbufs must have the same number " +
                "of channels");

        if (optimized_transformations == null)
            build_optimized_transformations();

        int n_channels = source.get_n_channels();
        int rowstride = source.get_rowstride();
        int width = source.get_width();
        int height = source.get_height();
        int rowbytes = n_channels * width;
        unowned uchar[] source_pixels = source.get_pixels();
        unowned uchar[] dest_pixels = dest.get_pixels();
        for (int j = 0; j < height; j++) {
            int row_start_index = j * rowstride;
            int row_end_index = row_start_index + rowbytes;
            for (int i = row_start_index; i < row_end_index; i += n_channels) {
                RGBAnalyticPixel current_pixel = RGBAnalyticPixel.from_quantized_components(
                    source_pixels[i], source_pixels[i + 1], source_pixels[i + 2]);

                current_pixel = apply_transformations(current_pixel);

                dest_pixels[i] = current_pixel.quantized_red();
                dest_pixels[i + 1] = current_pixel.quantized_green();
                dest_pixels[i + 2] = current_pixel.quantized_blue();
            }

            if ((cancellable != null) && (cancellable.is_cancelled())) {
                return;
            }
        }
    }
}

class RGBHistogram {
    private const uchar MARKED_BACKGROUND = 30;
    private const uchar MARKED_FOREGROUND = 210;
    private const uchar UNMARKED_BACKGROUND = 120;

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
                red_counts[pixel_data[r_offset]] += 1;
                green_counts[pixel_data[g_offset]] += 1;
                blue_counts[pixel_data[b_offset]] += 1;

                r_offset += pixel_bytes;
                g_offset += pixel_bytes;
                b_offset += pixel_bytes;
            }
        }
    }
    
    private int correct_snap_to_quantization(int[] buckets, int i) {
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
    
    private int correct_snap_from_quantization(int[] buckets, int i) {
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

    private void smooth_extrema(ref int[] count_data) {
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
        
        smooth_extrema(ref qualitative_red_counts);
        smooth_extrema(ref qualitative_green_counts);
        smooth_extrema(ref qualitative_blue_counts);
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

            /* detect pathological case of bilevel black & white images -- in this case, draw
               a blank histogram and return it to the caller */
            if (max_count == 0) {
                for (int i = 0; i < (pixel_bytes * graphic.width * graphic.height); i++) {
                    pixel_data[i] = UNMARKED_BACKGROUND;
                }
                return graphic;
            }

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
        int n_channels = pixbuf.get_n_channels();
        int rowstride = pixbuf.get_rowstride();
        int width = pixbuf.get_width();
        int height = pixbuf.get_height();
        int rowbytes = n_channels * width;
        unowned uchar[] pixels = pixbuf.get_pixels();
        for (int j = 0; j < height; j++) {
            int row_start_index = j * rowstride;
            int row_end_index = row_start_index + rowbytes;
            for (int i = row_start_index; i < row_end_index; i += n_channels) {
                RGBAnalyticPixel pix_rgb = RGBAnalyticPixel.from_quantized_components(
                    pixels[i], pixels[i + 1], pixels[i + 2]);
                HSVAnalyticPixel pix_hsi = HSVAnalyticPixel.from_rgb(pix_rgb);
                int quantized_light_value = (int)(pix_hsi.light_value * 255.0f);
                counts[quantized_light_value] += 1;
            }
        }    

        float pixel_count = (float)(pixbuf.width * pixbuf.height);
        float accumulator = 0.0f;
        for (int i = 0; i < 256; i++) {
            probabilities[i] = ((float) counts[i]) / pixel_count;
            accumulator += probabilities[i];
            cumulative_probabilities[i] = accumulator;
        }
    }

    public float get_cumulative_probability(int level) {
        // clamp out-of-range pixels to prevent crashing. 
        level = level.clamp(0, 255);
        return cumulative_probabilities[level];
    }
}

public class ExpansionTransformation : HSVTransformation {
    private float[] remap_table = null;
    private const float LOW_DISCARD_MASS = 0.02f;
    private const float HIGH_DISCARD_MASS = 0.02f;

    private int low_kink;
    private int high_kink;

    public ExpansionTransformation(IntensityHistogram histogram) {
        base(PixelTransformationType.TONE_EXPANSION);
        
        remap_table = new float[256];

        float LOW_KINK_MASS = LOW_DISCARD_MASS;
        low_kink = 0;
        while (histogram.get_cumulative_probability(low_kink) < LOW_KINK_MASS)
            low_kink++;
        
        float HIGH_KINK_MASS = 1.0f - HIGH_DISCARD_MASS;
        high_kink = 255;
        while ((histogram.get_cumulative_probability(high_kink) > HIGH_KINK_MASS) && (high_kink > 0))
                 high_kink--;

        build_remap_table();
    }
    
    public ExpansionTransformation.from_extrema(int black_point, int white_point) {
        base(PixelTransformationType.TONE_EXPANSION);

        white_point = white_point.clamp(0, 255);
        black_point = black_point.clamp(0, 255);

        if (black_point == white_point) {
            if (black_point == 0)
                white_point = 1;
            else if (white_point == 255)
                black_point = 254;
            else
                black_point = white_point - 1;
        }

        low_kink = black_point;
        high_kink = white_point;

        build_remap_table();        
    }

    public ExpansionTransformation.from_string(string encoded_transformation) {
        base(PixelTransformationType.TONE_EXPANSION);
        
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

    public override HSVAnalyticPixel transform_pixel_hsv(HSVAnalyticPixel pixel) {
        int remap_index = (int)(pixel.light_value * 255.0f);

        HSVAnalyticPixel result = pixel;
        result.light_value = remap_table[remap_index];

        result.light_value = result.light_value.clamp(0.0f, 1.0f);

        return result;
    }

    public override string to_string() {
        return "{ %d, %d }".printf(low_kink, high_kink);
    }

    public int get_white_point() {
        return high_kink;
    }

    public int get_black_point() {
        return low_kink;
    }

    public override bool is_identity() {
        return ((low_kink == 0) && (high_kink == 255));
    }

    public override PixelTransformation copy() {
        return new ExpansionTransformation.from_extrema(low_kink, high_kink);
    }
}

public class ShadowDetailTransformation : HSVTransformation {
    private const float MAX_EFFECT_SHIFT = 0.5f;
    private const float MIN_TONAL_WIDTH = 0.1f;
    private const float MAX_TONAL_WIDTH = 1.0f;
    private const float TONAL_WIDTH = 1.0f;

    private float intensity = 0.0f;
    private float[] remap_table = null;
    
    public const float MIN_PARAMETER = 0.0f;
    public const float MAX_PARAMETER = 32.0f;

    public ShadowDetailTransformation(float user_intensity) {
        base(PixelTransformationType.SHADOWS);
        
        intensity = user_intensity;
        float intensity_adj = (intensity / MAX_PARAMETER).clamp(0.0f, 1.0f);

        float effect_shift = MAX_EFFECT_SHIFT * intensity_adj;
        HermiteGammaApproximationFunction func =
            new HermiteGammaApproximationFunction(TONAL_WIDTH);
        
        remap_table = new float[256];
        for (int i = 0; i < 256; i++) {
            float x = ((float) i) / 255.0f;
            float weight = func.evaluate(x);
            remap_table[i] = (weight * (x + effect_shift)) + ((1.0f - weight) * x);
        }
    }

    public override HSVAnalyticPixel transform_pixel_hsv(HSVAnalyticPixel pixel) {
        HSVAnalyticPixel result = pixel;
        result.light_value = (remap_table[(int)(pixel.light_value * 255.0f)]).clamp(0.0f, 1.0f);
        return result;
    }

    public override PixelTransformation copy() {
        return new ShadowDetailTransformation(intensity);
    }
    
    public override bool is_identity() {
        return (intensity == 0.0f);
    }

    public float get_parameter() {
        return intensity;
    }
}

public class HermiteGammaApproximationFunction {
    private float x_scale = 1.0f;
    private float nonzero_interval_upper = 1.0f;
    
    public HermiteGammaApproximationFunction(float user_interval_upper) {
        nonzero_interval_upper = user_interval_upper.clamp(0.1f, 1.0f);
        x_scale = 1.0f / nonzero_interval_upper;
    }
    
    public float evaluate(float x) {
        if (x < 0.0f)
            return 0.0f;
        else if (x > nonzero_interval_upper)
            return 0.0f;
        else {
            float indep_var = x_scale * x;
            
            float dep_var =  6.0f * ((indep_var * indep_var * indep_var) -
                (2.0f * (indep_var * indep_var)) + (indep_var));
            
            return dep_var.clamp(0.0f, 1.0f);
        }
    }
}

public class HighlightDetailTransformation : HSVTransformation {
    private const float MAX_EFFECT_SHIFT = 0.5f;
    private const float MIN_TONAL_WIDTH = 0.1f;
    private const float MAX_TONAL_WIDTH = 1.0f;
    private const float TONAL_WIDTH = 1.0f;

    private float intensity = 0.0f;
    private float[] remap_table = null;
    
    public const float MIN_PARAMETER = -32.0f;
    public const float MAX_PARAMETER = 0.0f;

    public HighlightDetailTransformation(float user_intensity) {
        base(PixelTransformationType.HIGHLIGHTS);
        
        intensity = user_intensity;
        float intensity_adj = (intensity / MIN_PARAMETER).clamp(0.0f, 1.0f);

        float effect_shift = MAX_EFFECT_SHIFT * intensity_adj;
        HermiteGammaApproximationFunction func =
            new HermiteGammaApproximationFunction(TONAL_WIDTH);
        
        remap_table = new float[256];
        for (int i = 0; i < 256; i++) {
            float x = ((float) i) / 255.0f;
            float weight = func.evaluate(1.0f - x);
            remap_table[i] = (weight * (x - effect_shift)) + ((1.0f - weight) * x);
        }
    }

    public override HSVAnalyticPixel transform_pixel_hsv(HSVAnalyticPixel pixel) {
        HSVAnalyticPixel result = pixel;
        result.light_value = (remap_table[(int)(pixel.light_value * 255.0f)]).clamp(0.0f, 1.0f);
        return result;
    }

    public override PixelTransformation copy() {
        return new HighlightDetailTransformation(intensity);
    }
    
    public override bool is_identity() {
        return (intensity == 0.0f);
    }

    public float get_parameter() {
        return intensity;
    }
}

namespace AutoEnhance {
    const int SHADOW_DETECT_MIN_INTENSITY = 8;
    const int SHADOW_DETECT_MAX_INTENSITY = 100;
    const int SHADOW_DETECT_INTENSITY_RANGE = SHADOW_DETECT_MAX_INTENSITY -
            SHADOW_DETECT_MIN_INTENSITY;
    const float SHADOW_MODE_HIGH_DISCARD_MASS = 0.02f;
    const float SHADOW_AGGRESSIVENESS_MUL = 0.4f;
    const int EMPIRICAL_DARK = 30;

public PixelTransformationBundle create_auto_enhance_adjustments(Gdk.Pixbuf pixbuf) {
    PixelTransformationBundle adjustments = new PixelTransformationBundle();

    IntensityHistogram analysis_histogram = new IntensityHistogram(pixbuf);
    /* compute the percentage of pixels in the image that fall into the shadow range --
       this measures "of the pixels in the image, how many of them are in shadow?" */
    float pct_in_range =
        100.0f *(analysis_histogram.get_cumulative_probability(SHADOW_DETECT_MAX_INTENSITY) -
        analysis_histogram.get_cumulative_probability(SHADOW_DETECT_MIN_INTENSITY));

    /* compute the mean intensity of the pixels that are in the shadow range -- this measures
       "of those pixels that are in shadow, just how dark are they?" */
    float shadow_range_mean_prob_val =
        (analysis_histogram.get_cumulative_probability(SHADOW_DETECT_MIN_INTENSITY) +
        analysis_histogram.get_cumulative_probability(SHADOW_DETECT_MAX_INTENSITY)) * 0.5f;
    int shadow_mean_intensity = SHADOW_DETECT_MIN_INTENSITY;
    for ( ; shadow_mean_intensity <= SHADOW_DETECT_MAX_INTENSITY; shadow_mean_intensity++) {
        if (analysis_histogram.get_cumulative_probability(shadow_mean_intensity) >= shadow_range_mean_prob_val)
            break;
    }

    /* if more than 40 percent of the pixels in the image are in the shadow detection range,
       or if the mean intensity within the shadow range is less than 50 (an empirically
       determined threshold below which pixels appear very dark), regardless of the
       percent of pixels in it, then perform shadow detail enhancement. Otherwise,
       skip shadow detail enhancement and perform a traditional contrast expansion */
    if ((pct_in_range > 40.0f) || (pct_in_range > 20.0f) && (shadow_mean_intensity < EMPIRICAL_DARK)) {
        float shadow_trans_effect_size = ((((float) SHADOW_DETECT_MAX_INTENSITY) -
            ((float) shadow_mean_intensity)) / ((float) SHADOW_DETECT_INTENSITY_RANGE)) *
            ShadowDetailTransformation.MAX_PARAMETER;

        shadow_trans_effect_size *= SHADOW_AGGRESSIVENESS_MUL;

        adjustments.set(new ShadowDetailTransformation(shadow_trans_effect_size));
            
        /* if shadow detail expansion is being performed, we still perform contrast expansion,
           but only on the top end */
        int discard_point = 255;
        for ( ; discard_point > -1; discard_point--) {
            if ((1.0f - analysis_histogram.get_cumulative_probability(discard_point)) >
                SHADOW_MODE_HIGH_DISCARD_MASS)
                    break;
        }
        
        adjustments.set(new ExpansionTransformation.from_extrema(0, discard_point));
    }
    else {
        adjustments.set(new ExpansionTransformation(analysis_histogram));
        adjustments.set(new ShadowDetailTransformation(0));
    }
    /* zero out any existing color transformations as these may conflict with
       auto-enhancement */
    adjustments.set(new HighlightDetailTransformation(0.0f));
    adjustments.set(new TemperatureTransformation(0.0f));
    adjustments.set(new TintTransformation(0.0f));
    adjustments.set(new ExposureTransformation(0.0f));
    adjustments.set(new SaturationTransformation(0.0f));
    
    return adjustments;
}
}

