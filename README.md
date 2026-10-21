# Laymo

Laymo is a project to build a custom hardware accelerator for **LiDAR-based
3D object detection**. The goal is to turn a LiDAR point cloud into 3D
bounding boxes around objects. Our starting architecture follows
[PointPillars](https://openaccess.thecvf.com/content_CVPR_2019/papers/Lang_PointPillars_Fast_Encoders_for_Object_Detection_From_Point_Clouds_CVPR_2019_paper.pdf).

```text
LiDAR points → pillars → learned pillar features → bird's-eye-view grid
             → CNN backbone → detection head → 3D bounding boxes
```

## Proposed pipeline

1. **Assign points to pillars.** Divide the ground plane into a fixed grid
   and assign each point to a vertical pillar using its x and y coordinates.
   This step is deterministic, so we can start with a software implementation
   and move it to hardware only if profiling shows a need.

2. **Build point features.** In the original PointPillars design, each point
   has nine features: x, y, z, intensity; its x, y, and z offsets from the
   mean point in its pillar; and its x and y offsets from the pillar center.

3. **Encode each pillar.** A learned pillar feature network compresses the
   points in each pillar into one feature vector. We plan to train the model
   in software and load its learned weights into the accelerator.

4. **Create the bird's-eye-view (BEV) grid.** Place each pillar's feature
   vector at its x-y location in a 2D feature map. Empty grid cells remain
   empty or zero-filled.

5. **Run the BEV CNN backbone.** Convolutions process the BEV feature map and
   produce new feature maps. This is our main target for hardware
   acceleration. The integer MAC and systolic array in this repository are
   early building blocks for that work.

6. **Run the detection head.** A second CNN uses predefined 3D anchor boxes
   as starting guesses and predicts, for each anchor, a class confidence,
   box adjustments, and a direction bin for the heading.

7. **Decode and filter boxes.** Apply the predicted adjustments to the
   anchors to produce candidate 3D boxes. Remove low-confidence candidates,
   sort the rest by confidence, and use non-maximum suppression to discard
   lower-confidence boxes that overlap a stronger box too much. A simple
   pairwise implementation can take quadratic time in the number of
   candidates.

## Hardware focus

We are starting with a 128 x 128 systolic array of signed integer
multiply-accumulate units. To turn it into a complete BEV CNN accelerator,
we still need to define weight and activation formats, memory buffers,
convolution scheduling, layer control, and how the trained model is loaded.
We will measure both detection accuracy and hardware cost as those choices
become concrete.
