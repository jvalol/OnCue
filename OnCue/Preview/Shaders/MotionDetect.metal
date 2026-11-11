//
//  MotionDetect.metal
//  OnCue
//
//  Created by Jake Van Alstyne on 12/20/19.
//  Copyright © 2019 Jake Van Alstyne. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

// Compute kernel
// Whether this variant writes the preview at all (spec 0041). Resolved when the pipeline state is
// built, so the mask-only variant has no branch and never touches textures 3 and 4.
constant bool writesPreview [[function_constant(0)]];

// Two outputs (spec 0040). outputTexture is the mask the CPU sampler reads: frame pixel where
// nothing changed, (red, 0, 0) where something did. Its arithmetic is unchanged from 2019 and must
// stay so, because CameraPipeline.measureMotion counts "green and blue zero, red not" off it and
// every user's threshold is calibrated against that count. previewTexture is what the preview
// window shows: the unblurred current frame, with changed pixels blended toward red by one fixed
// amount, so motion is as plain as before and the thing moving stays visible through it.
kernel void motionDetect(texture2d<half, access::read>  lastTexture  [[ texture(0) ]],
                         texture2d<half, access::read>  currentTexture  [[ texture(1) ]],
                         texture2d<half, access::write> outputTexture [[ texture(2) ]],
                         texture2d<half, access::write> previewTexture [[ texture(3) ]],
                         texture2d<half, access::read>  rawCurrentTexture [[ texture(4) ]],
                         uint2 gid [[thread_position_in_grid]])
{
  // Don't read or write outside of the texture.
  if ((gid.x >= currentTexture.get_width()) || (gid.y >= currentTexture.get_height())) {
    return;
  }

  half4 lastInputColor = lastTexture.read(gid);
  half4 currentInputColor = currentTexture.read(gid);

  half4 difference = half4(currentInputColor.r - lastInputColor.r,
                           currentInputColor.g - lastInputColor.g,
                           currentInputColor.b - lastInputColor.b,
                           1.0);
  float deltaDotP = dot(difference, difference);
  float red = 1.5 * (deltaDotP - 1.0);
  bool changed = deltaDotP > 1.2;

  half4 outputColor = changed ? half4(red, 0.0, 0.0, 1.0) : lastInputColor;
  outputTexture.write(outputColor, gid);

  if (writesPreview) {
    const half overlay = 0.8h;
    half4 picture = rawCurrentTexture.read(gid);
    half4 previewColor = changed ? mix(picture, half4(1.0h, 0.0h, 0.0h, 1.0h), overlay) : picture;
    previewTexture.write(half4(previewColor.rgb, 1.0h), gid);
  }
}
