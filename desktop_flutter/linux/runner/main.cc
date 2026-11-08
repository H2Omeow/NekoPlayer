#include "crash_handler.h"
#include "my_application.h"

#include <fontconfig/fontconfig.h>

int main(int argc, char** argv) {
  crash_handler_install(APPLICATION_ID);
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* font = g_build_filename(
        directory, "data", "flutter_assets", "assets", "fonts",
        "NotoSansCJKsc-Regular.otf", nullptr);
    if (!FcConfigAppFontAddFile(nullptr, reinterpret_cast<const FcChar8*>(font))) {
      g_warning("Could not load the bundled CJK font for desktop lyrics.");
    }
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
