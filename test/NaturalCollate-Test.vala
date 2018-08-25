void add_trailing_numbers_tests () {
    Test.add_func ("/functional/collation/trailing_numbers", () => {
            string a = "100foo";
            string b = "100bar";
            string coll_a = NaturalCollate.collate_key(a);
            string coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a, coll_b) > 0);
            assert(strcmp(a,b) > 0);
            assert(NaturalCollate.compare(a,b) == strcmp(coll_a, coll_b));

            string atrail = "00100foo";
            string btrail = "0100bar";

            string coll_atrail = NaturalCollate.collate_key(a);
            string coll_btrail = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a, coll_atrail) == 0);
            assert(strcmp(coll_b, coll_btrail) == 0);

            assert(strcmp(coll_atrail, coll_btrail) > 0);
            assert(strcmp(atrail,btrail) < 0);
            assert(NaturalCollate.compare(atrail,btrail) == strcmp(coll_atrail, coll_btrail));

        });
}

void add_numbers_tail_tests () {
    Test.add_func ("/functional/collation/numbers_tail", () => {
            string a = "aaa00100";
            string b = "aaa02";
            string coll_a = NaturalCollate.collate_key(a);
            string coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a, coll_b) > 0);
            assert(strcmp(a,b) < 0);
            assert(NaturalCollate.compare(a,b) == strcmp(coll_a, coll_b));
        });
}

void add_dots_tests () {
    Test.add_func ("/functional/collation/dots", () => {
            string sa = "Foo01.jpg";
            string sb = "Foo2.jpg";
            string sc = "Foo3.jpg";
            string sd = "Foo10.jpg";

            assert (strcmp(sa, sd) < 0);
            assert (strcmp(sd, sb) < 0);
            assert (strcmp(sb, sc) < 0);

            string coll_sa = NaturalCollate.collate_key(sa);
            string coll_sb = NaturalCollate.collate_key(sb);
            string coll_sc = NaturalCollate.collate_key(sc);
            string coll_sd = NaturalCollate.collate_key(sd);

            assert (strcmp(coll_sa, coll_sb) < 0);
            assert (strcmp(coll_sb, coll_sc) < 0);
            assert (strcmp(coll_sc, coll_sd) < 0);
        });
}

void add_bigger_as_strcmp_tests () {
    Test.add_func ("/functional/collation/bigger_as_strcmp", () => {
            string a = "foo";
            string b = "bar";
            string coll_a = NaturalCollate.collate_key(a);
            string coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a,coll_b) > 0);
            assert(strcmp(a,b) > 0);
            assert(NaturalCollate.compare(a,b) == strcmp(coll_a, coll_b));

            a = "foo0001";
            b = "bar0000";
            coll_a = NaturalCollate.collate_key(a);
            coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a,coll_b) > 0);
            assert(strcmp(a,b) > 0);
            assert(NaturalCollate.compare(a,b) == strcmp(coll_a, coll_b));

            a = "bar010";
            b = "bar01";
            coll_a = NaturalCollate.collate_key(a);
            coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a,coll_b) > 0);
            assert(strcmp(a,b) > 0);
            assert(NaturalCollate.compare(a,b) == strcmp(coll_a, coll_b));
        });
}

void add_numbers_tests() {
    Test.add_func ("/functional/collation/numbers", () => {
            string a = "0";
            string b = "1";
            string coll_a = NaturalCollate.collate_key(a);
            string coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a, coll_b) < 0);

            a = "100";
            b = "101";
            coll_a = NaturalCollate.collate_key(a);
            coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a, coll_b) < 0);

            a = "2";
            b = "10";
            coll_a = NaturalCollate.collate_key(a);
            coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a, coll_b) < 0);

            a = "b20";
            b = "b100";
            coll_a = NaturalCollate.collate_key(a);
            coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a, coll_b) < 0);
        });
}

void add_ignore_leading_zeros_tests () {
    Test.add_func ("/functional/collation/ignore_leading_zeros", () => {
            string a = "bar0000010";
            string b = "bar10";
            string coll_a = NaturalCollate.collate_key(a);
            string coll_b = NaturalCollate.collate_key(b);
            assert(strcmp(coll_a,coll_b) == 0);
        });
}

void main (string[] args) {
    GLib.Intl.setlocale(GLib.LocaleCategory.ALL, "");
    Test.init (ref args);
    add_trailing_numbers_tests();
    add_numbers_tail_tests();
    add_bigger_as_strcmp_tests();
    add_ignore_leading_zeros_tests();
    add_numbers_tests();
    add_dots_tests();
    Test.run();
}
