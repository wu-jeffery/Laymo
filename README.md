Laymo is a project to build a custom hardware accelerator for LiDAR-based 3D object detection. It aims to process LiDAR point clouds efficiently and produce 3D bounding boxes around objects.

## Tests

The integer MAC and systolic-array testbenches are in [`rtl/dv`](rtl/dv). Run `make test` for the quick suite or `make test-array` for the full 128×128 array test.
