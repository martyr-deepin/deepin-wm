[CCode (cprefix = "Meta", gir_namespace = "Meta", gir_version = "3.0", lower_case_cprefix = "meta_")]
namespace Meta {
    [CCode (cname = "meta_verbose_real", cheader_filename = "meta/main.h")]
    public static void verbose (string format, ...);

    [CCode (cheader_filename = "meta/main.h", cname = "meta_topic_real")]
    public static void topic (Meta.DebugTopic topic, string format, ...);

#if HAS_MUTTER314
        [CCode (cheader_filename = "meta/main.h", cname = "meta_set_debugging")]
        public static void set_debugging (bool setting);
        [CCode (cheader_filename = "meta/main.h", cname = "meta_set_verbose")]
        public static void set_verbose (bool setting);
#endif
}
