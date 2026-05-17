// SPDX-License-Identifier: LGPL-2.0-or-later
// SPDX-FileCopyrightText: 2016 Software Freedom Convervancy Inc.

/* we define our own measurement enum instead of using the Gtk.Unit enum
   provided by Gtk+ 2.0 because Gtk.Unit doesn't define a CENTIMETERS
   constant (though it does define an MM for millimeters). This is
   unfortunate, because in metric countries people like to think about
   paper sizes for printing in CM not MM. so, to avoid having to
   multiply and divide everything by 10 (which is error prone) to convert
   from CM to MM and vice-versa whenever we read or write measurements, we
   eschew Gtk.Unit and substitute our own */
public enum MeasurementUnit {
    INCHES,
    CENTIMETERS
}

public struct Measurement {
    private const double CENTIMETERS_PER_INCH = 2.54;
    private const double INCHES_PER_CENTIMETER = (1.0 / 2.54);

    public double value;
    public MeasurementUnit unit;

    public Measurement(double value, MeasurementUnit unit) {
        this.value = value;
        this.unit = unit;
    }

    public Measurement convert_to(MeasurementUnit to_unit) {
        if (unit == to_unit)
            return this;

        if (to_unit == MeasurementUnit.INCHES) {
            return Measurement(value * INCHES_PER_CENTIMETER, MeasurementUnit.INCHES);
        } else if (to_unit == MeasurementUnit.CENTIMETERS) {
            return Measurement(value * CENTIMETERS_PER_INCH, MeasurementUnit.CENTIMETERS);
        } else {
            error("unrecognized unit");
        }
    }

    public bool is_less_than(Measurement rhs) {
        Measurement converted_rhs = (unit == rhs.unit) ? rhs : rhs.convert_to(unit);
        return (value < converted_rhs.value);
    }

    public bool is_greater_than(Measurement rhs) {
        Measurement converted_rhs = (unit == rhs.unit) ? rhs : rhs.convert_to(unit);
        return (value > converted_rhs.value);
    }
}
