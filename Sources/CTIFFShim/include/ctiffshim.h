// Thin C layer over libtiff for Swift (docs/TECH_SPEC.md §4.4). Swift cannot call libtiff's variadic
// TIFFGetField, and keeping libtiff's headers out of Swift means the module needs no extra search paths.
// Each handle is NOT thread-safe: use one per thread (TIFFRegionSource keeps a pool).
#ifndef CTIFFSHIM_H
#define CTIFFSHIM_H

#include <stdint.h>

typedef struct vv_tiff vv_tiff;

typedef struct {
    uint32_t width, height;
    uint32_t tile_width, tile_height;   // 0 when stored in strips
    uint32_t rows_per_strip;
    uint32_t subfile_type;              // bit 0: reduced resolution, bit 2: mask
    uint16_t samples_per_pixel, bits_per_sample, sample_format;   // 1 uint, 2 int, 3 float
    uint16_t photometric, planar_config, compression, orientation, extra_samples;
    uint16_t subifd_count;
    int32_t  tiled;
} vv_dir_info;

/// Opens read-only, memory-mapped; libtiff's error and warning output is silenced. NULL on failure.
vv_tiff *vv_open(const char *path);
void vv_close(vv_tiff *t);

/// Number of top-level directories (pages, overviews, masks).
int32_t vv_directory_count(vv_tiff *t);
/// Selects a top-level directory (0-based). Returns 1 on success.
int32_t vv_set_directory(vv_tiff *t, uint32_t index);
/// Selects a directory by file offset (SubIFDs). Returns 1 on success.
int32_t vv_set_subdirectory(vv_tiff *t, uint64_t offset);
/// Reads the current directory's facts. Returns 1 on success.
int32_t vv_dir_info_get(vv_tiff *t, vv_dir_info *info);
/// Copies up to `max` SubIFD offsets of the current directory; returns how many there are.
int32_t vv_subifds(vv_tiff *t, uint64_t *offsets, int32_t max);
/// ICC profile of the current directory (pointer valid until the directory changes). Returns 1 if present.
int32_t vv_icc_profile(vv_tiff *t, const void **data, uint32_t *length);

/// Decodes the rectangle (x, y, w, h) of the current directory as 8-bit RGBA, top-left first, using
/// libtiff's RGBA interface (handles palette, YCbCr, CMYK, JPEG, 1-bit …). `raster` holds w*h words with
/// R in the low byte. Returns 1 on success.
int32_t vv_read_rgba_rect(vv_tiff *t, uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t *raster);

/// Raw decoded bytes of one tile (x, y = any pixel inside it) or one strip (y = any row inside it), for
/// contiguous (chunky) data. Returns the byte count, or -1.
int64_t vv_tile_size(vv_tiff *t);
int64_t vv_strip_size(vv_tiff *t);
int64_t vv_read_tile(vv_tiff *t, uint32_t x, uint32_t y, void *buffer, int64_t size);
int64_t vv_read_strip(vv_tiff *t, uint32_t row, void *buffer, int64_t size);

/// libtiff version string.
const char *vv_version(void);

#endif
