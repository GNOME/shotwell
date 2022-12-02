public struct MetadataRational {
    public int numerator;
    public int denominator;

    public MetadataRational.invalid() {
        this.numerator = -1;
        this.denominator = -1;
    }

    public MetadataRational(int numerator, int denominator) {
        this.numerator = numerator;
        this.denominator = denominator;
    }

    private bool is_component_valid(int component) {
        return (component >= 0) && (component <= 1000000);
    }

    public bool is_valid() {
        return (is_component_valid(numerator) && is_component_valid(denominator));
    }

    public string to_string() {
        return (is_valid()) ? ("%d/%d".printf(numerator, denominator)) : "";
    }
}
