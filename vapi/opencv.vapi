/**
 * OpenCV Vala Bindings
 * Copyright 2010 Evan Nemerson <evan@coeus-group.com>
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/* Status:
 *   Core is mostly done, as is HighGUI. Auxiliary is almost
 *   completely unbound. I'm not sure when, or if, I will have time to
 *   finish these.
 */

[CCode (cheader_filename = "cv.h", cprefix = "Cv", lower_case_cprefix = "cv")]
namespace OpenCV {
	[Compact, CCode (cname = "CvArr", has_type_id = false)]
	public class Array {
		[CCode (cname = "cvGetCol")]
		public OpenCV.Matrix get_col (OpenCV.Matrix submat, int col);
		[CCode (cname = "cvGetCols")]
		public OpenCV.Matrix get_cols (OpenCV.Matrix submat, int start_col, int end_col);
		[CCode (cname = "cvGetDiag")]
		public OpenCV.Matrix get_diagonal (OpenCV.Matrix submat, int diag = 0);
		[CCode (cname = "cvGetDimSize")]
		public int get_dimension_size (int index);
		[CCode (cname = "cvGetDims")]
		public int get_dimensions (int[]? sizes = null);
		[CCode (cname = "cvGetElemType")]
		public OpenCV.Type get_elem_type ();
		[CCode (cname = "cvGetImage")]
		public OpenCV.IPL.Image get_image (OpenCV.IPL.Image header);
		[CCode (cname = "cvGetMat")]
		public OpenCV.Matrix get_matrix (OpenCV.Matrix header, int[]? coi = null, int allowND = 0);
		[CCode (cname = "cvGetRow")]
		public OpenCV.Matrix get_row (OpenCV.Matrix submat, int row);
		[CCode (cname = "cvGetRows")]
		public OpenCV.Matrix get_rows (OpenCV.Matrix submat, int start_row, int end_Row, int delta_row = 1);
		[CCode (cname = "cvGetSubRect")]
		public OpenCV.Matrix get_subrectangle (OpenCV.Matrix submat, OpenCV.Rectangle rect);

		[CCode (cname = "cvAdd")]
		public void add (OpenCV.Array src2, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvAddS")]
		public void add_scalar (OpenCV.Scalar value, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvSub")]
		public void subtract (OpenCV.Array src2, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvSubS")]
		public void subtract_scalar (OpenCV.Scalar value, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvSubRS")] // what is "R"? "subtract_r_scalar" sucks
		public void subtract_r_scalar (OpenCV.Scalar value, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvMul")]
		public void multiply (OpenCV.Array src2, OpenCV.Array dst, double scale = 1.0);
		[CCode (cname = "cvDiv")]
		public void divide (OpenCV.Array src2, OpenCV.Array dst, double scale = 1.0);
		[CCode (cname = "cvScaleAdd")]
		public void scale_add (OpenCV.Scalar scale, OpenCV.Array src2, OpenCV.Array dst);
		[CCode (cname = "cvAddWeighted")]
		public void add_weighted (double alpha, OpenCV.Array src2, double beta, double gamma, OpenCV.Array dst);
		[CCode (cname = "cvDotProduct")]
		public double dot_product (OpenCV.Array src2);
		[CCode (cname = "cvAnd")]
		public void and (OpenCV.Array src2, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvAndS")]
		public void and_scalar (OpenCV.Scalar value, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvOr")]
		public void or (OpenCV.Array src2, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvOrS")]
		public void or_scalar (OpenCV.Scalar value, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvXor")]
		public void xor (OpenCV.Array src2, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvXorS")]
		public void xor_scalar (OpenCV.Scalar value, OpenCV.Array dst, OpenCV.Array? mask = null);
		[CCode (cname = "cvNot")]
		public void not (OpenCV.Array dst);
		[CCode (cname = "cvInRange")]
		public void in_range (OpenCV.Array lower, OpenCV.Array upper, OpenCV.Array dst);
		[CCode (cname = "cvInRangeS")]
		public void in_range_scalar (OpenCV.Scalar lower, OpenCV.Scalar upper, OpenCV.Array dst);
		[CCode (cname = "cvCmp")]
		public void compare (OpenCV.Array src2, OpenCV.Array dst, OpenCV.ComparisonOperator cmp_op = OpenCV.ComparisonOperator.EQUAL);
		[CCode (cname = "cvCmpS")]
		public void compare_scalar (double value, OpenCV.Array dst, OpenCV.ComparisonOperator cmp_op = OpenCV.ComparisonOperator.EQUAL);
		[CCode (cname = "cvMin")]
		public void min (OpenCV.Array src2, OpenCV.Array dst);
		[CCode (cname = "cvMax")]
		public void max (OpenCV.Array src2, OpenCV.Array dst);
		[CCode (cname = "cvMinS")]
		public void min_scalar (double value, OpenCV.Array dst);
		[CCode (cname = "cvMaxS")]
		public void max_scalar (double value, OpenCV.Array dst);
		[CCode (cname = "cvAbsDiff")]
		public void abs_diff (OpenCV.Array src2, OpenCV.Array dst);
		[CCode (cname = "cvAbsDiffS")]
		public void abs_diff_scalar (OpenCV.Array dst, OpenCV.Scalar value);
		[CCode (cname = "cvAbs")]
		public void abs (OpenCV.Array dst);

		[CCode (cname = "cvCartToPolar")]
		public static void cartesian_to_polar (OpenCV.Array x, OpenCV.Array y, OpenCV.Array magnitude, OpenCV.Array? angle = null, int angle_in_degrees = 0);
		[CCode (cname = "cvPolarToCart")]
		public static void polar_to_cartesian (OpenCV.Array magnitude, OpenCV.Array angle, OpenCV.Array x, OpenCV.Array y, int angle_in_degress = 0);
		[CCode (cname = "cvPow")]
		public void pow (OpenCV.Array dst, double power);
		[CCode (cname = "cvExp")]
		public void exp (OpenCV.Array dst);
		[CCode (cname = "cv")]
		public void log (OpenCV.Array dst);
		[CCode (cname = "cvCheckArr")]
		public int check_array (OpenCV.Check flags = 0, double min_val = 0.0, double max_val = 0.0);
		[CCode (cname = "cvSort")]
		public void sort (OpenCV.Array? dst = null, OpenCV.Array? idxmat = null, OpenCV.Sort flags = OpenCV.Sort.EVERY_ROW | OpenCV.Sort.ASCENDING);
		[CCode (cname = "cvCrossProduct")]
		public void cross_product (OpenCV.Array src2, OpenCV.Array dst);
		[CCode (cname = "cvMatMulAdd")]
		public void matrix_multiply_add (OpenCV.Array src2, OpenCV.Array? src3, OpenCV.Array dst);
		[CCode (cname = "cvMatMul")]
		public void matrix_multiply (OpenCV.Array src2, OpenCV.Array dst);
		[CCode (cname = "cvGEMM")]
		public void GEMM (OpenCV.Array src2, double alpha, OpenCV.Array src3, double beta, OpenCV.Array dst, OpenCV.GEMMTranspose tABC = 0);
		[CCode (cname = "cvTransform")]
		public void transform (OpenCV.Array dst, OpenCV.Matrix transmat, OpenCV.Matrix? shiftvec = null);
		[CCode (cname = "cvPerspectiveTransform")]
		public void perspective_transform (OpenCV.Array dst, OpenCV.Matrix mat);
		[CCode (cname = "cvMulTransposed")]
		public void multiply_transposed (OpenCV.Array dst, int order, OpenCV.Array? delta = null, double scale = 1.0);
		[CCode (cname = "cvTranspose")]
		public void transpose (OpenCV.Array? dst = null);
		[CCode (cname = "cvFlip")]
		public void flip (OpenCV.Array? dst = null, OpenCV.FlipMode flip_mode = OpenCV.FlipMode.HORIZONTAL);
		[CCode (cname = "cvSVD")]
		public void SVD (OpenCV.Array w, OpenCV.Array? u = null, OpenCV.Array? v = null, OpenCV.SVDFlag flags = 0);
		[CCode (cname = "cvSVBkSb")]
		public static void SVBkSb (OpenCV.Array W, OpenCV.Array U, OpenCV.Array V, OpenCV.Array B, OpenCV.Array X, OpenCV.SVDFlag flags = 0);

		[CCode (cname = "cvLine")]
		public void line (OpenCV.Point pt1, OpenCV.Point pt2, OpenCV.Scalar color, int thickness = 1);
		[CCode (cname = "cvRectangle")]
		public void rectangle (OpenCV.Point pt1, OpenCV.Point pt2, OpenCV.Scalar color, int thickness = 1, int line_type = 8, int shift = 0);
		[CCode (cname = "cvCircle")]
		public void circle (OpenCV.Point center, int radius, OpenCV.Scalar color, int thickness = 1, int line_type = 8, int shift = 0);
		[CCode (cname = "cvEllipse")]
		public void ellipse (OpenCV.Point center, OpenCV.Size axes, double angle, double start_angle, double end_angle, OpenCV.Scalar color, int thickness = 1);
		[CCode (cname = "cvEllipseBox")]
		public void ellipse_box (OpenCV.Box2D box, OpenCV.Scalar color, int thickness = 1, int line_type = 8, int shift = 0);
		[CCode (cname = "cvFillConvexPoly")]
		public void fill_convex_polygon (OpenCV.Point[] pts, OpenCV.Scalar color, int line_type = 8, int shift = 0);
		[CCode (cname = "cvFillPoly")]
		public void fill_polygon ([CCode (array_length = false)] OpenCV.Point[][] pts, [CCode (array_length = false)] int[] npts, int contours, OpenCV.Scalar color, int line_type = 8, int shift = 0);
		[CCode (cname = "cvPolyLine")]
		public void poly_line ([CCode (array_length = false)] OpenCV.Point[][] pts, [CCode (array_length = false)] int[] npts, int contours, int is_closed, OpenCV.Scalar color, int thickness = 1, int line_type = 8, int shift = 0);
		[CCode (cname = "cvSegmentImage", cheader_filename = "cvaux.h")]
		public OpenCV.Sequence segment_image (OpenCV.Array dstarr, double canny_threshhold, double ffill_threshhold, OpenCV.Memory.Storage storage);
		[CCode (cname = "cvConvert")]
		public void convert (OpenCV.Array dst);
	}

	[SimpleType, CCode (cname = "CvBox2D", has_type_id = false)]
	public struct Box2D {
		public OpenCV.Point2D32f center;
		public OpenCV.Size2D32f size;
		public float angle;
	}

	[Flags, CCode (cname = "int", has_type_id = false, lower_case_cprefix = "CV_CHECK_")]
	public enum Check {
		RANGE,
		QUIET
	}

	[CCode (cname = "int", has_type_id = false, lower_case_cprefix = "CV_CMP_")]
	public enum ComparisonOperator {
		EQ,
		GT,
		GE,
		LT,
		LE,
		NE,

		[CCode (cname = "CV_CMP_EQ")]
		EQUAL,
		[CCode (cname = "CV_CMP_GT")]
		GREATER_THAN,
		[CCode (cname = "CV_CMP_GE")]
		GRATER_THAN_OR_EQUAL,
		[CCode (cname = "CV_CMP_LT")]
		LESS_THAN,
		[CCode (cname = "CV_CMP_LE")]
		LESS_THAN_OR_EQUAL,
		[CCode (cname = "CV_CMP_NE")]
		NOT_EQUAL
	}

	[Compact, CCode (cname = "CvEHMM", cheader_filename = "cvaux.h", free_function = "cvRelease2DHMM", free_function_address_of = true)]
	public class EHMM {
		[CCode (cname = "cvCreate2DHMM")]
		public EHMM.2D ([CCode (array_length = false)] int[] stateNumber, [CCode (array_length = false)] int[] numMix, int obsSize);

		[CCode (cname = "cvUniformImgSegm", instance_pos = -1)]
		public void uniform_image_segment (OpenCV.EHMM.ImageObservationInfo obs);
		[CCode (cname = "cvInitMixSegm", instance_pos = -1)]
		public void init_mix_segment (OpenCV.EHMM.ImageObservationInfo[] obs_info_array);
		[CCode (cname = "cvEstimateHMMStateParams", instance_pos = -1)]
		public void estimate_state_params (OpenCV.EHMM.ImageObservationInfo[] obs_info_array);
		[CCode (cname = "cvEstimateTransProb", instance_pos = -1)]
		public void estimate_transition_probability (OpenCV.EHMM.ImageObservationInfo[] obs_info_array);
		[CCode (cname = "cvEstimateObsProb", instance_pos = -1)]
		public void estimate_observation_probability (OpenCV.EHMM.ImageObservationInfo obs_info);
		[CCode (cname = "cvEViterbi", instance_pos = -1)]
		public void viterbi (OpenCV.EHMM.ImageObservationInfo obs_info);
		[CCode (cname = "cvMixSegmL2", instance_pos = -1)]
		public void mix_segm_l2 (OpenCV.EHMM.ImageObservationInfo[] obs_info_array);

		public int level;
		[CCode (array_length_cname = "num_states")]
		public float[] transP;
		[CCode (array_length = false)]
		public float[][] obsProb;
		public OpenCV.EHMM.StateInfo u;

		[Compact, CCode (cname = "CvEHMMState")]
		public class State {
			[CCode (array_length_cname = "num_mix")]
			public float[] mu;
			[CCode (array_length_cname = "num_mix")]
			public float[] inv_var;
			[CCode (array_length_cname = "num_mix")]
			public float[] log_var_val;
			[CCode (array_length_cname = "num_mix")]
			public float[] weight;
		}

		public struct StateInfo {
			public OpenCV.EHMM.State state;
			public OpenCV.EHMM ehmm;
		}

		[Compact, CCode (cname = "CvImgObsInfo", free_function = "cvReleaseObsInfo", free_function_address_of = true)]
		public class ImageObservationInfo {
			public ImageObservationInfo (OpenCV.Size numObs, int obsSize);

			// [CCode (cname = "CV_COUNT_OBS", instance_pos = -1)]
			// public void count (roi, win, delta);
		}
	}

	[CCode (cname = "int", has_type_id = false)]
	public enum FlipMode {
		[CCode (cname = "0")]
		HORIZONTAL,
		[CCode (cname = "1")]
		VERTICAL,
		[CCode (cname = "-1")]
		BOTH
	}

	[CCode (cname = "int", has_type_id = false, cprefix = "CV_FONT_")]
	public enum FontFace {
		HERSHEY_SIMPLEX,
		HERSHEY_PLAIN,
		HERSHEY_DUPLEX,
		HERSHEY_COMPLEX,
		HERSHEY_TRIPLEX,
		HERSHEY_COMPLEX_SMALL,
		HERSHEY_SCRIPT_SIMPLEX,
		HERSHEY_SCRIPT_COMPLEX,
		ITALIC,
		VECTOR0
	}

	[Flags, CCode (cname = "int", has_type_id = false)]
	public enum GEMMTranspose {
		[CCode (cname = "CV_GEMM_A_T")]
		A,
		[CCode (cname = "CV_GEMM_B_T")]
		B,
		[CCode (cname = "CV_GEMM_C_T")]
		C
	}

	[CCode (cname = "CvLineIterator", has_type_id = false)]
	public struct LineIterator {
		[CCode (cname = "cvInitLineIterator")]
		public LineIterator (OpenCV.Array image, OpenCV.Point pt1, OpenCV.Point pt2, int connectivity = 8, int left_to_right = 0);

		public int err;
		public int plus_delta;
		public int minus_delta;
		public int plus_step;
		public int minus_step;
	}

	[Flags, CCode (cname = "int", has_type_id = false, lower_case_cprefix = "CV_SORT_")]
	public enum Sort {
		EVERY_ROW,
		EVERY_COLUMN,
		ASCENDING,
		DESCENDING
	}

	[Flags, CCode (cname = "int", has_type_id = false, lower_case_cprefix = "CV_SVD_")]
	public enum SVDFlag {
		MODIFY_A,
		U_T,
		V_T
	}

	[CCode (cname = "int", has_type_id = false)]
	public enum Type {
		[CCode (cname = "CV_8U")]
		U8,
		[CCode (cname = "CV_8S")]
		S8,
		[CCode (cname = "CV_16U")]
		U16,
		[CCode (cname = "CV_16S")]
		S16,
		[CCode (cname = "CV_32S")]
		S32,
		[CCode (cname = "CV_32F")]
		F32,
		[CCode (cname = "CV_64F")]
		F64,
		[CCode (cname = "CV_USRTYPE1")]
		USR1,

		[CCode (cname = "CV_CV_8UC1")]
		UC8_1,
		[CCode (cname = "CV_8UC2")]
		UC8_2,
		[CCode (cname = "CV_8UC3")]
		UC8_3,
		[CCode (cname = "CV_8UC4")]
		UC8_4,

		[CCode (cname = "CV_8SC1")]
		SC8_1,
		[CCode (cname = "CV_8SC2")]
		SC8_2,
		[CCode (cname = "CV_8SC3")]
		SC8_3,
		[CCode (cname = "CV_8SC4")]
		SC8_4,

		[CCode (cname = "CV_16UC1")]
		UC16_1,
		[CCode (cname = "CV_16UC2")]
		UC16_2,
		[CCode (cname = "CV_16UC3")]
		UC16_3,
		[CCode (cname = "CV_16UC4")]
		UC16_4,

		[CCode (cname = "CV_16SC1")]
		SC16_1,
		[CCode (cname = "CV_16SC2")]
		SC16_2,
		[CCode (cname = "CV_16SC3")]
		SC16_3,
		[CCode (cname = "CV_16SC4")]
		SC16_4,

		[CCode (cname = "CV_32SC1")]
		SC32_1,
		[CCode (cname = "CV_32SC2")]
		SC32_2,
		[CCode (cname = "CV_32SC3")]
		SC32_3,
		[CCode (cname = "CV_32SC4")]
		SC32_4,

		[CCode (cname = "CV_32FC1")]
		FC32_1,
		[CCode (cname = "CV_32FC2")]
		FC32_2,
		[CCode (cname = "CV_32FC3")]
		FC32_3,
		[CCode (cname = "CV_32FC4")]
		FC32_4,

		[CCode (cname = "CV_64FC1")]
		FC64_1,
		[CCode (cname = "CV_64FC2")]
		FC64_2,
		[CCode (cname = "CV_64FC3")]
		FC64_3,
		[CCode (cname = "CV_64FC4")]
		FC64_4
	}

	[CCode (cname = "CvFont", has_type_id = false, destroy_function = "", has_copy_function = false)]
	public struct Font {
		[CCode (cname = "cvInitFont")]
		public Font (OpenCV.FontFace font_face, double hscale, double vscale, double shear = 0.0, int thickness = 1, int line_type = 8);

		[CCode (cname = "cvGetTextSize", instance_pos = 1.9)]
		public void get_text_size (string text_string, out OpenCV.Size text_size, out int baseline);

		public OpenCV.FontFace font_face;
		[CCode (array_length = false, array_null_terminated = true)]
		public int[] ascii;
		[CCode (array_length = false, array_null_terminated = true)]
		public int[] greek;
		[CCode (array_length = false, array_null_terminated = true)]
		public int[] cyrillic;
		public float hscale;
		public float vscale;
		public int thickness;
		public float dx;
		public int line_type;
	}

	[Compact, CCode (cname = "CvHaarClassifierCascade")]
	public class HaarClassifierCascade {
		[CCode (cname = "cvLoad", type = "void*")]
		public static unowned HaarClassifierCascade? load (string filename, OpenCV.Memory.Storage storage, string? name = null, out string? real_name = null);

		[CCode (cname = "cvHaarDetectObjects", instance_pos = 1.9)]
		public unowned OpenCV.Sequence<OpenCV.Rectangle?> detect_objects (OpenCV.Array image, OpenCV.Memory.Storage storage, double scale_factor = 1.0, int min_neighbors = 3, OpenCV.HaarClassifierCascade.Flags flags = 0, OpenCV.Size min_size = OpenCV.Size (0, 0));
		[CCode (cname = "cvSetImagesForHaarClassifierCascade")]
		public void set_images (OpenCV.Array sum, OpenCV.Array sqsum, OpenCV.Array tilted_sum, double scale);
		[CCode (cname = "cvRunHaarClassifierCascade")]
		public int run (OpenCV.Point pt, int start_stage = 0);

		[Flags, CCode (cname = "int", has_type_id = false, cprefix = "CV_HAAR_")]
		public enum Flags {
			DO_CANNY_PRUNING,
			SCALE_IMAGE,
			FIND_BIGGEST_OBJECT,
			DO_ROUGH_SEARCH
		}
	}

	[SimpleType, CCode (cname = "CvInput")]
	public struct Input {
		public OpenCV.Callback @callback;
		public void* data;
	}

	[Compact, CCode (cname = "CvMat", has_type_id = false, free_function = "cvReleaseMat", free_function_address_of = true, copy_function = "cvCloneMat")]
	public class Matrix : OpenCV.Array {
		[CCode (cname = "cvCreateMat")]
		public Matrix (int rows, int cols, int type);
		[CCode (cname = "cvCreateMatHeader")]
		public Matrix.header (int rows, int cols, int type);

		[CCode (cname = "cvCloneMat")]
		public Matrix clone ();
		[CCode (cname = "cvCompleteSymm")]
		public void complete_symmetric (int LtoR);
		[CCode (cname = "cvIplDepth")]
		public static int depth (int type);
		[CCode (cname = "cvmGet")]
		public double get (int row, int col);
		[CCode (cname = "cvmSet")]
		public void set (int row, int col, double value);
		[CCode (cname = "cvSolveCubic")]
		public int solve_cubic (OpenCV.Matrix roots);
		[CCode (cname = "cvSolvePoly")]
		public void solve_polynomial (OpenCV.Matrix roots2, int maxiter = 20, int fig = 100);

		public OpenCV.Type type;
		public int step;
		public int rows;
		public int cols;
		public OpenCV.Matrix.Data data;

		[CCode (cname = "union { uchar* ptr; short* s; int* i; float* fl; double* db; }", has_type_id = false)]
		public struct Data {
			public void* ptr;
			public short* s;
			public int* i;
			public float* fl;
			public double* db;
		}

		[Compact, CCode (cname = "cvMatND", has_type_id = false, free_function = "cvReleaseMatND", free_function_address_of = true, copy_function = "cvCloneMatND")]
		public class ND {
			[CCode (cname = "cvCreateMatND")]
			public ND (int dims, [CCode (array_length = false, array_null_terminated = true)] int[] sizes, int type);

			[CCode (cname = "cvCloneMatND")]
			public ND clone ();

			public OpenCV.Type type;
			public int dims;
			public OpenCV.Matrix.Data data;
			// TODO: s/32/OpenCV.MAX_DIM/ when b.g.o. #624507 is resolved
			public OpenCV.Matrix.ND.Dimension dim[32];

			public struct Dimension {
				public int size;
				public int step;
			}
		}

		[Compact, CCode (cname = "cvSparseMat", has_type_id = false, free_function = "cvReleaseSparseMat", free_function_address_of = true, copy_function = "cvCloneSparseMat")]
		public class Sparse {
			[CCode (cname = "cvCreateSparseMat")]
			public Sparse (int dims, [CCode (array_length = false, array_null_terminated = true)] int[] sizes, int type);

			[CCode (cname = "cvCloneSparseMat")]
			public Sparse clone ();

			public OpenCV.Type type;
			public int dims;
			// public struct CvSet* heap;
			// public void** hashtable;
			// public int hashsize;
			[CCode (cname = "valoffset")]
			public int value_offset;
			[CCode (cname = "idxoffset")]
			public int index_offset;
			// TODO: s/32/OpenCV.MAX_DIM/ when b.g.o. #624507 is resolved
			public int size[32];

			[CCode (cname = "CvSparseNode", has_type_id = false)]
			public struct Node {
				[CCode (cname = "hashval")]
				public uint hash_value;
				public Node* next;
			}

			[CCode (cname = "CvSparseMatIterator", has_type_id = false)]
			public struct Iterator {
				[CCode (cname = "mat")]
				public OpenCV.Matrix.Sparse matrix;
				public Node* node;
				[CCode (cname = "curidx")]
				public int current_index;
			}
		}
	}

	[CCode (cname = "CvString")]
	public class String {
		[CCode (cname = "cvMemStorageAllocString")]
		public String (OpenCV.Memory.Storage storage, string str, int len = -1);

		public int len;
		public string ptr;
	}

	namespace Math {
		[CCode (cname = "cvCeil")]
		public static int ceil (double value);
		[CCode (cname = "cvCbrt")]
		public static float cubic_root (float value);
		[CCode (cname = "cvFastArctan")]
		public static float fast_arctan (float x, float y);
		[CCode (cname = "cvFloor")]
		public static int floor (double value);
		[CCode (cname = "cvInvSqrt")]
		public static float inv_sqrt ();
		[CCode (cname = "cvIsInf")]
		public static int is_inf (double value);
		[CCode (cname = "cvIsNaN")]
		public static int is_nan (double value);
		[CCode (cname = "cvRound")]
		public static int round (double value);
		[CCode (cname = "cvSqrt")]
		public static float sqrt (double value);
	}

	namespace Memory {
		[Compact, CCode (cname = "CvMemBlock")]
		public struct Block {
			public OpenCV.Memory.Block? prev;
			public OpenCV.Memory.Block? next;
		}

		[Compact, CCode (cname = "CvMemStorage", free_function = "cvReleaseMemStorage", free_function_address_of = true)]
		public class Storage {
			[CCode (cname = "cvCreateMemStorage")]
			public Storage (int block_size = 0);
			[CCode (cname = "cvCreateChildMemStorage")]
			public Storage.from_parent (OpenCV.Memory.Storage parent);

			[CCode (cname = "cvClearMemStorage")]
			public void clear ();
			[CCode (cname = "cvSaveMemStoragePos")]
			public void save_position (OpenCV.Memory.Storage.Position pos);
			[CCode (cname = "cvRestoreMemStoragePos")]
			public void restore_position (OpenCV.Memory.Storage.Position pos);
			[CCode (cname = "cvMemStorageAlloc")]
			public void* alloc (size_t size);
			[CCode (cname = "cvMemStorageAllocString")]
			public OpenCV.String alloc_string (string ptr, int len = -1);

			[CCode (cname = "cvLoad", instance_pos = 1.9)]
			public void* load (string filename, string name, out string? real_name = null);

			public int signature;
			public OpenCV.Memory.Block bottom;
			public OpenCV.Memory.Block top;
			public OpenCV.Memory.Storage parent;
			public int block_size;
			public int free_space;

			[CCode (cname = "CvMemStoragePos")]
			public struct Position {
				public OpenCV.Memory.Block top;
				public int free_space;
			}
		}

		[CCode (cname = "cvAlloc")]
		public static void* alloc ();
		[CCode (cname = "cvFree")]
		public static void free (void* ptr);
	}

	[SimpleType, CCode (cname = "CvPoint", has_type_id = false)]
	public struct Point {
		[CCode (cname = "cvPoint")]
		public Point (int x, int y);
		[CCode (cname = "cvPointFrom32f")]
		public Point.from_32f (OpenCV.Point2D32f point);

		[CCode (cname = "cvPointTo32f")]
		public Point to_32f ();

		public int x;
		public int y;
	}

	[CCode (cname = "CvPoint2D32f", has_type_id = false)]
	public struct Point2D32f {
		public float x;
		public float y;

		[CCode (cname = "cvPoint2D32f")]
		public Point2D32f (float x, float y);
		[CCode (cname = "cvPointTo32f")]
		public Point2D32f.from_point (OpenCV.Point point);

		[CCode (cname = "cvPointFrom32f")]
		public Point to_point (OpenCV.Point2D32f point);
	}

	[CCode (cname = "CvPoint2D32f", has_type_id = false)]
	public struct Point2D64f {
		[CCode (cname = "cvPoint2D64f")]
		public Point2D64f (double x, double y);

		public double x;
		public double y;
	}

	[CCode (cname = "CvPoint3D32f", has_type_id = false)]
	public struct Point3D32f {
		[CCode (cname = "cvPoint3D32f")]
		public Point3D32f (float x, float y, float z);

		public float x;
		public float y;
		public float z;
	}

	[CCode (cname = "CvPoint3D64f")]
	public struct Point3D64f {
		[CCode (cname = "cvPoint3D64f")]
		public Point3D64f (double x, double y, double z);

		public double x;
		public double y;
		public double z;
	}

	[SimpleType, CCode (cname = "CvRect", has_type_id = false, destroy_function = "")]
	public struct Rectangle {
		[CCode (cname = "cvRect")]
		public Rectangle (int x, int y, int width, int height);
		[CCode (cname = "cvRectToROI")]
		public OpenCV.IPL.ROI to_roi (int coi);

		public int x;
		public int y;
		public int width;
		public int height;
	}

	[SimpleType, CCode (cname = "CvScalar", has_type_id = false, destroy_function = "")]
	public struct Scalar {
		[CCode (cname = "cvScalar")]
		public Scalar (double val0, double val1 = 0.0, double val2 = 0.0, double val3 = 0.0);
		[CCode (cname = "cvScalarAll")]
		public Scalar.all (double val0123);
		[CCode (cname = "cvRawDataToScalar")]
		public Scalar.from_raw_data ([CCode (array_length = false)] uint8[] data, int type);
		[CCode (cname = "cvColorToScalar")]
		public Scalar.from_color (double packed_color, int arrtype);
		[CCode (cname = "CV_RGB")]
		public Scalar.from_rgb (double red, double green, double blue);

		[CCode (cname = "cvScalarToRawData")]
		public void to_raw_data ([CCode (array_length = false)] uint8[] data, int type, int extend_to_12 = 0);

		public double val[4];
	}

	[Compact, CCode (cname = "CvSeq", free_function = "")]
	public class Sequence<T> {
		[CCode (cname = "cvCreateSeq")]
		public Sequence (int seq_flags, int header_size, int elem_size, OpenCV.Memory.Storage storage);

		[CCode (cname = "cvSetSeqBlockSize")]
		public void set_block_size (int delta_elems);
		[CCode (cname = "cvSeqPush")]
		public unowned T push (T element);
		[CCode (cname = "cvSeqPushFront")]
		public unowned T push_front (T element);
		[CCode (cname = "cvSeqPop")]
		public void pop (T element = null);
		[CCode (cname = "cvSeqPopFront")]
		public void pop_front (T element = null);
		[CCode (cname = "cvGetSeqElem")]
		public unowned T? get (int index);
		[CCode (cname = "cvSeqPushMulti")]
		public void push_multi (T[] elements, bool in_front = false);
		[CCode (cname = "cvSeqPopMulti")]
		public void pop_multi (T[] elements, bool in_front = false);
		[CCode (cname = "cvSeqInsert")]
		public void insert (int before_index, T element);
		[CCode (cname = "cvSeqRemove")]
		public void remove (int index);
		[CCode (cname = "cvClearSeq")]
		public void clear (int index);
		[CCode (cname = "cvCvtSeqToArray", array_length_pos = 1.9)]
		public T[]? to_array (OpenCV.Slice slice = OpenCV.Slice.WHOLE_ARRAY);

		public int total;
	}

	[SimpleType, CCode (cname = "CvSize", has_type_id = false)]
	public struct Size {
		public int width;
		public int height;

		[CCode (cname = "cvSize")]
		public Size (int width, int height);
	}

	public struct Size2D32f {
		[CCode (cname = "cvSize2D32f")]
		public Size2D32f (double width, double heigh);

		public float width;
		public float height;
	}

	[SimpleType, CCode (cname = "CvSlice")]
	public struct Slice {
		public int start_index;
		public int end_index;

		[CCode (cname = "cvSlice")]
		public Slice (int start, int end);
		[CCode (cname = "cvSliceLength")]
		public int length (OpenCV.Sequence seq);

		[CCode (cname = "CV_WHOLE_ARR")]
		public const OpenCV.Slice WHOLE_ARRAY;
	}

	[SimpleType, CCode (cname = "CvTermCriteria", has_type_id = false)]
	public struct TermCriteria {
		public OpenCV.Type type;
		public int max_iter;
		public double epsilon;

		[CCode (cname = "cvTermCriteria")]
		public TermCriteria (int type, int max_iter, double epsilon);
	}

	[CCode (cheader_filename = "highgui.h")]
	namespace Window {
		[CCode (cname = "cvNamedWindow")]
		public static int create_named (string window_name, OpenCV.Window.Flags flags = OpenCV.Window.Flags.AUTO_SIZE);
		[CCode (cname = "cvShowImage")]
		public static void show_image (string window_name, OpenCV.Array arr);
		[CCode (cname = "cvDestroyWindow")]
		public static void destroy (string window_name);
		[CCode (cname = "cvGetWindowProperty")]
		public static void get_property (string window_name, OpenCV.Window.Property prop_id);
		[CCode (cname = "cvSetWindowProperty")]
		public static void set_property (string window_name, OpenCV.Window.Property prop_id, double value);
		[CCode (cname = "cvResizeWindow")]
		public static void resize (string window_name, int width, int height);
		[CCode (cname = "cvMoveWindow")]
		public static void move (string window_name, int x, int y);
		[CCode (cname = "cvDestroyAllWindows")]
		public static void destroy_all ();
		[CCode (cname = "cvGetWindowHandle")]
		public static void* get_handle (string window_name);
		[CCode (cname = "cvGetWindowName")]
		public static unowned string get_name (void* handle);
		[CCode (cname = "cvSetMouseCallback")]
		public static void set_mouse_callback (string window_name, OpenCV.MouseCallback on_mouse);

		[Flags, CCode (cname = "int", has_type_id = false, cprefix = "CV_WINDOW_")]
		public enum Flags {
			[CCode (cname = "CV_WINDOW_AUTOSIZE")]
			AUTO_SIZE
		}

		[CCode (cname = "int", has_type_id = false, cprefix = "CV_WND_PROP_")]
		public enum Property {
			FULLSCREEN,
			AUTOSIZE
		}
	}

	[CCode (cheader_filename = "highgui.h")]
	namespace Trackbar {
		[CCode (cname = "CvTrackBarCallback2")]
		public delegate void Callback (int pos);

		[CCode (cname = "cvCreateTrackbar2")]
		public int create (string trackbar_name, string window_name, ref int value, int count, OpenCV.Trackbar.Callback on_change);
		[CCode (cname = "cvGetTrackbarPos")]
		public int get_position (string trackbar_name, string window_name);
		[CCode (cname = "cvSetTrackbarPos")]
		public void set_position (string trackbar_name, string window_name, int pos);
	}

	[CCode (cname = "int", has_type_id = false, cprefix = "CV_EVENT_", cheader_filename = "highgui.h")]
	public enum EventType {
		[CCode (cname = "CV_EVENT_MOUSEMOVE")]
		MOUSE_MOVE,
		[CCode (cname = "CV_EVENT_LBUTTONDOWN")]
		LEFT_BUTTON_DOWN,
		[CCode (cname = "CV_EVENT_RBUTTONDOWN")]
		RIGHT_BUTTON_DOWN,
		[CCode (cname = "CV_EVENT_MBUTTONDOWN")]
		MIDDLE_BUTTON_DOWN,
		[CCode (cname = "CV_EVENT_LBUTTONUP")]
		LEFT_BUTTON_UP,
		[CCode (cname = "CV_EVENT_RBUTTONUP")]
		RIGHT_BUTTON_UP,
		[CCode (cname = "CV_EVENT_MBUTTONUP")]
		MIDDLE_BUTTON_UP,
		[CCode (cname = "CV_EVENT_LBUTTONDBLCLK")]
		LEFT_BUTTON_DOUBLE_CLICK,
		[CCode (cname = "CV_EVENT_RBUTTONDBLCLK")]
		RIGHT_BUTTON_DOUBLE_CLICK,
		[CCode (cname = "CV_EVENT_MBUTTONDBLCLK")]
		MIDDLE_BUTTON_DOUBLE_CLICK,

		MOUSEMOVE,
		LBUTTONDOWN,
		RBUTTONDOWN,
		MBUTTONDOWN,
		LBUTTONUP,
		RBUTTONUP,
		MBUTTONUP,
		LBUTTONDBLCLK,
		RBUTTONDBLCLK,
		MBUTTONDBLCLK,
	}

	[Flags, CCode (cname = "int", has_type_id = false, cprefix = "CV_EVENT_FLAG_", cheader_filename = "highgui.h")]
	public enum EventFlag {
		[CCode (cname = "CV_EVENT_FLAG_LBUTTON")]
		LEFT_BUTTON,
		[CCode (cname = "CV_EVENT_FLAG_RBUTTON")]
		RIGHT_BUTTON,
		[CCode (cname = "CV_EVENT_FLAG_MBUTTON")]
		MIDDLE_BUTTON,
		[CCode (cname = "CV_EVENT_FLAG_CTRLKEY")]
		CONTROL_KEY,
		[CCode (cname = "CV_EVENT_FLAG_SHIFTKEY")]
		SHIFT_KEY,
		[CCode (cname = "CV_EVENT_FLAG_ALTKEY")]
		ALT_KEY,

		LBUTTON,
		RBUTTON,
		MBUTTON,
		CTRLKEY,
		SHIFTKEY,
		ALTKEY
	}

	[Compact, CCode (cname = "CvCapture", free_function = "cvReleaseCapture", free_function_address_of = true, has_type_id = false, cheader_filename = "highgui.h")]
	public class Capture {
		[CCode (cname = "cvCreateFileCapture")]
		public Capture.from_file (string filename);
		[CCode (cname = "cvCreateCameraCapture")]
		public Capture.from_camera (int index);

		[CCode (cname = "cvGrabFrame")]
		public bool grab_frame ();
		[CCode (cname = "cvRetrieveFrame")]
		public unowned OpenCV.IPL.Image retrieve_frame (int stream_index = 0);
		[CCode (cname = "cvQueryFrame")]
		public unowned OpenCV.IPL.Image query_frame ();
		[CCode (cname = "cvGetCaptureProperty")]
		public double get_property (OpenCV.Capture.Property property_id);
		[CCode (cname = "cvSetCaptureProperty")]
		public int set_property (OpenCV.Capture.Property property_id, double value);
		[CCode (cname = "cvGetCaptureDomain")]
		public OpenCV.Capture.Domain get_domain ();

		[CCode (cname = "int", has_type_id = false, cprefix = "CV_CAP_")]
		public enum Domain {
			ANY,
			MIL,
			VFW,
			V4L,
			V4L2,
			FIREWARE,
			FIREWIRE,
			IEEE1394,
			DC1394,
			CMU1394,
			STEREO,
			TYZX,
			[CCode (cname = "CV_TYZX_LEFT")]
			TYZX_LEFT,
			[CCode (cname = "CV_TYZX_RIGHT")]
			TYZX_RIGHT,
			[CCode (cname = "CV_TYZX_COLOR")]
			TYZX_COLOR,
			[CCode (cname = "CV_TYZX_Z")]
			TYZX_Z,
			QT,
			UNICAP,
			DSHOW,
			PVAPI
		}

		[CCode (cname = "int", has_type_id = false, cprefix = "CV_CAP_PROP_")]
		public enum Property {
			POS_MSEC,
			POS_FRAMES,
			POS_AVI_RATIO,
			FRAME_WIDTH,
			FRAME_HEIGHT,
			FPS,
			FOURCC,
			FRAME_COUNT,
			FORMAT,
			MODE,
			BRIGHTNESS,
			CONTRAST,
			SATURATION,
			HUE,
			GAIN,
			EXPOSURE,
			CONVERT_RGB,
			WHITE_BALANCE,
			RECTIFICATION,
		}
	}

	[CCode (cname = "CV_MAX_DIM")]
	public const int MAX_DIM;

	[CCode (cname = "CvCallback")]
	public delegate void Callback (int index, void* buffer);
	[CCode (cname = "CvMouseCallback")]
	public delegate void MouseCallback (OpenCV.EventType ev, int x, int y, OpenCV.EventFlag flags);

	[CCode (cname = "cvWaitKey")]
	public static void wait_key (int delay = 0);

	[CCode (cheader_filename = "cvaux.h")]
	namespace Eigen {
		[CCode (cname = "cvCalcCovarMatrixEx")]
		public static void calculate_covariation_matrix (int nObjects, void* input, int ioFlags, [CCode (array_length_pos = 3.9)] uint8[] buffer, void* user_data, OpenCV.IPL.Image avg, [CCode (array_length = false)] float[] covar_matrix);
		[CCode (cname = "cvCalcEigenObjects")]
		public static void calculate_objects (int nObjects, void* input, void* output, int ioFlags, int ioBufSize, void* userData, OpenCV.TermCriteria calc_limit, OpenCV.IPL.Image avg, [CCode (array_length = false)] float[] eigenvals);
		[CCode (cname = "cvClacDecompCoeff")]
		public static double calculate_decomposition_coefficient (OpenCV.IPL.Image obj, OpenCV.IPL.Image eigObj, OpenCV.IPL.Image avg);
		[CCode (cname = "cvEigenDecomposite")]
		public static void eigen_decomposite (OpenCV.IPL.Image obj, int nEigObjs, void* eigInput, int ioFlags, void* userData, OpenCV.IPL.Image avg, [CCode (array_length = false)] float[] coeffs);
		[CCode (cname = "cvEigenProjection")]
		public static void eigen_projection (void* eigInput, int nEigObjs, int ioFlags, void* userData, [CCode (array_length = false)] float[] coeffs, OpenCV.IPL.Image avg, OpenCV.IPL.Image proj);
	}

	[CCode (cprefix = "Ipl")]
	namespace IPL {
		[Compact, CCode (cname = "IplImage", has_type_id = false, free_function = "cvReleaseImage", free_function_address_of = true, copy_function = "cvCloneImage")]
		public class Image : OpenCV.Array {
			[CCode (cname = "cvCreateImage")]
			public Image (OpenCV.Size size, int depth, int channels);
			[CCode (cname = "cvLoadImage", cheader_filename = "highgui.h")]
			public Image.load (string filename, OpenCV.IPL.Image.LoadType type = OpenCV.IPL.Image.LoadType.COLOR);

			[CCode (cname = "cvCloneImage")]
			public Image clone ();
			[CCode (cname = "cvInitImageHeader")]
			public void init_header (OpenCV.Size size, int depth, int channels, int origin = 0, int align = 4);
			[CCode (cname = "cvGetImageCOI")]
			public int get_coi ();
			[CCode (cname = "cvGetImageROI")]
			public OpenCV.Rectangle get_roi ();
			[CCode (cname = "cvResetImageROI")]
			public int reset_roi ();
			[CCode (cname = "cvSetImageROI")]
			public void set_roi (OpenCV.Rectangle roi);
			[CCode (cname = "cvSetImageCOI")]
			public void set_coi (int coi);

			[CCode (cname = "nSize")]
			public int n_size;
			[CCode (cname = "ID")]
			public int id;
			[CCode (cname = "nChannels")]
			public int n_channels;
			[CCode (cname = "alphaChannel")]
			public int alpha_channel;
			public int depth;
			[CCode (cname = "colorModel")]
			public char color_model[4];
			[CCode (cname = "channelSeq")]
			public char channel_sequence[4];
			[CCode (cname = "dataOrder")]
			public int data_order;
			public int origin;
			public int align;
			public int width;
			public int height;
			public OpenCV.IPL.ROI* roi;
			[CCode (cname = "maskROI")]
			public Image mask_roi;
			[CCode (cname = "imageId")]
			public void* image_id;
			// [CCode (cname = "tileInfo")]
			// public TileInfo tile_info;
			[CCode (cname = "imageData", array_length_cname = "imageSize")]
			public uint8[] image_data;
			[CCode (cname = "widthStep")]
			public int width_step;
			[CCode (cname = "BorderMode")]
			public int border_mode[4];
			[CCode (cname = "BorderConst")]
			public int border_const[4];
			// [CCode (cname = "imageDataOrigin")]
			// public ? image_data_origin;

			[CCode (cname = "int", has_type_id = false, cprefix = "CV_LOAD_IMAGE_")]
			public enum LoadType {
				UNCHANGED,
				GRAYSCALE,
				COLOR,
				[CCode (cname = "CV_LOAD_IMAGE_ANYDEPTH")]
				ANY_DEPTH,
				[CCode (cname = "CV_LOAD_IMAGE_ANYCOLOR")]
				ANY_COLOR
			}
		}

		[SimpleType, CCode (cname = "IplROI", has_type_id = false)]
		public struct ROI {
			public int coi;
			[CCode (cname = "xOffset")]
			public int x_offset;
			[CCode (cname = "yOffset")]
			public int y_offset;
			public int width;
			public int height;

			[CCode (cname = "cvROIToRect")]
			public OpenCV.Rectangle to_rectangle ();
		}

		[CCode (cname = "IplConvKernel", has_type_id = false)]
		public struct ConvKernel {
			[CCode (cname = "nCols")]
			public int n_cols;
			[CCode (cname = "nRows")]
			public int n_rows;
			[CCode (cname = "anchorX")]
			public int anchor_x;
			[CCode (cname = "anchorY")]
			public int anchor_y;
			[CCode (array_length = false)]
			public int[] values;
			[CCode (cname = "nShiftR")]
			public int n_shift_r;
		}

		[CCode (cname = "IplConvKernelFP", has_type_id = false)]
		public struct ConvKernelFP {
			[CCode (cname = "nCols")]
			public int nCols;
			[CCode (cname = "nRows")]
			public int nRows;
			[CCode (cname = "anchorX")]
			public int anchorX;
			[CCode (cname = "anchorY")]
			public int anchorY;
			[CCode (array_length = false)]
			public float[] values;
		}
	}
}
