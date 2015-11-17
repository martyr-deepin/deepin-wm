[CCode (cprefix = "Meta", gir_namespace = "Meta", gir_version = "3.0", lower_case_cprefix = "meta_")]
namespace Meta {
    [CCode (cname = "meta_verbose_real", cheader_filename = "meta/main.h")]
    public static void verbose (string format, ...);

    [CCode (cheader_filename = "meta/main.h", cname = "meta_topic_real")]
    public static void topic (Meta.DebugTopic topic, string format, ...);
}
