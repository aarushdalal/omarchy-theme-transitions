# Wallpaper Engine decoder

The `src/extractor.py` and `src/tex_parser.py` modules come from the previously inspected Wallpaper Engine PKG/TEX Extractor by uKeps (MIT), retained with its license. They decode packages and textures as data; source shaders/scripts are never executed. LZ4 and texture decoding use the bundled Python implementation and Pillow.

The public reference normalizes trailing whitespace; copyright and license notices are retained.
