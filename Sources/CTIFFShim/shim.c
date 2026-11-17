#include "ctiffshim.h"
#include <tiffio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

struct vv_tiff { TIFF *tif; };

static void vv_quiet(const char *module, const char *fmt, va_list ap) { (void)module; (void)fmt; (void)ap; }

vv_tiff *vv_open(const char *path) {
    static int silenced = 0;
    if (!silenced) {
        TIFFSetErrorHandler(vv_quiet);
        TIFFSetWarningHandler(vv_quiet);
        silenced = 1;
    }
    TIFF *tif = TIFFOpen(path, "rm");   // "m" = memory-map when possible
    if (!tif) return NULL;
    vv_tiff *t = (vv_tiff *)calloc(1, sizeof(vv_tiff));
    t->tif = tif;
    return t;
}

void vv_close(vv_tiff *t) {
    if (!t) return;
    TIFFClose(t->tif);
    free(t);
}

int32_t vv_directory_count(vv_tiff *t) { return (int32_t)TIFFNumberOfDirectories(t->tif); }

int32_t vv_set_directory(vv_tiff *t, uint32_t index) { return TIFFSetDirectory(t->tif, (tdir_t)index) ? 1 : 0; }

int32_t vv_set_subdirectory(vv_tiff *t, uint64_t offset) { return TIFFSetSubDirectory(t->tif, offset) ? 1 : 0; }

int32_t vv_dir_info_get(vv_tiff *t, vv_dir_info *info) {
    TIFF *tif = t->tif;
    memset(info, 0, sizeof(*info));
    if (!TIFFGetField(tif, TIFFTAG_IMAGEWIDTH, &info->width)) return 0;
    if (!TIFFGetField(tif, TIFFTAG_IMAGELENGTH, &info->height)) return 0;
    info->tiled = TIFFIsTiled(tif) ? 1 : 0;
    if (info->tiled) {
        TIFFGetField(tif, TIFFTAG_TILEWIDTH, &info->tile_width);
        TIFFGetField(tif, TIFFTAG_TILELENGTH, &info->tile_height);
    }
    TIFFGetFieldDefaulted(tif, TIFFTAG_ROWSPERSTRIP, &info->rows_per_strip);
    TIFFGetFieldDefaulted(tif, TIFFTAG_SUBFILETYPE, &info->subfile_type);
    TIFFGetFieldDefaulted(tif, TIFFTAG_SAMPLESPERPIXEL, &info->samples_per_pixel);
    TIFFGetFieldDefaulted(tif, TIFFTAG_BITSPERSAMPLE, &info->bits_per_sample);
    TIFFGetFieldDefaulted(tif, TIFFTAG_SAMPLEFORMAT, &info->sample_format);
    if (!TIFFGetField(tif, TIFFTAG_PHOTOMETRIC, &info->photometric)) info->photometric = 0xFFFF;
    TIFFGetFieldDefaulted(tif, TIFFTAG_PLANARCONFIG, &info->planar_config);
    TIFFGetFieldDefaulted(tif, TIFFTAG_COMPRESSION, &info->compression);
    TIFFGetFieldDefaulted(tif, TIFFTAG_ORIENTATION, &info->orientation);
    uint16_t extra_count = 0;
    uint16_t *extra = NULL;
    if (TIFFGetField(tif, TIFFTAG_EXTRASAMPLES, &extra_count, &extra)) info->extra_samples = extra_count;
    uint16_t sub_count = 0;
    uint64_t *subs = NULL;
    if (TIFFGetField(tif, TIFFTAG_SUBIFD, &sub_count, &subs)) info->subifd_count = sub_count;
    return 1;
}

int32_t vv_subifds(vv_tiff *t, uint64_t *offsets, int32_t max) {
    uint16_t count = 0;
    uint64_t *subs = NULL;
    if (!TIFFGetField(t->tif, TIFFTAG_SUBIFD, &count, &subs)) return 0;
    for (int32_t i = 0; i < count && i < max; i++) offsets[i] = subs[i];
    return count;
}

int32_t vv_icc_profile(vv_tiff *t, const void **data, uint32_t *length) {
    uint32_t len = 0;
    void *ptr = NULL;
    if (!TIFFGetField(t->tif, TIFFTAG_ICCPROFILE, &len, &ptr) || !ptr || len == 0) return 0;
    *data = ptr;
    *length = len;
    return 1;
}

int32_t vv_read_rgba_rect(vv_tiff *t, uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t *raster) {
    char message[1024];
    TIFFRGBAImage img;
    if (!TIFFRGBAImageOK(t->tif, message)) return 0;
    if (!TIFFRGBAImageBegin(&img, t->tif, 0, message)) return 0;
    img.req_orientation = ORIENTATION_TOPLEFT;
    img.row_offset = (int)y;
    img.col_offset = (int)x;
    int ok = TIFFRGBAImageGet(&img, raster, w, h);
    TIFFRGBAImageEnd(&img);
    return ok ? 1 : 0;
}

int64_t vv_tile_size(vv_tiff *t) { return (int64_t)TIFFTileSize64(t->tif); }

int64_t vv_strip_size(vv_tiff *t) { return (int64_t)TIFFStripSize64(t->tif); }

int64_t vv_read_tile(vv_tiff *t, uint32_t x, uint32_t y, void *buffer, int64_t size) {
    uint32_t tile = TIFFComputeTile(t->tif, x, y, 0, 0);
    tmsize_t n = TIFFReadEncodedTile(t->tif, tile, buffer, (tmsize_t)size);
    return n < 0 ? -1 : (int64_t)n;
}

int64_t vv_read_strip(vv_tiff *t, uint32_t row, void *buffer, int64_t size) {
    uint32_t strip = TIFFComputeStrip(t->tif, row, 0);
    tmsize_t n = TIFFReadEncodedStrip(t->tif, strip, buffer, (tmsize_t)size);
    return n < 0 ? -1 : (int64_t)n;
}

const char *vv_version(void) { return TIFFGetVersion(); }
