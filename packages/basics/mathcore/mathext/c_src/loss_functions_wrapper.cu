/*
 * This file is part of the Neural Network modules of the APRIL toolkit (A
 * Pattern Recognizer In Lua).
 *
 * Copyright 2012, Salvador España-Boquera, Adrian Palacios Corella, Francisco
 * Zamora-Martinez
 *
 * The APRIL-ANN toolkit is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation
 *
 * This library is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
 * for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 *
 */
#include <cmath>
#include "clamp.h"
#include "cuda_utils.h"
#include "error_print.h"
#include "wrapper.h"
#include "unused_variable.h"
#include "april_assert.h"

using AprilUtils::clamp;

#define clip(value, min, max) (((value) < (min)) ? (min) : (((value) > (max)) ? (max) : (value)))

namespace AprilMath {

///////////////////////////////////////////////////////////
/////////////////// Kernels ///////////////////////////////
///////////////////////////////////////////////////////////

#ifdef USE_CUDA
__global__ void computeMSELossFunctionKernel(const float *output,
					     const float *target_output,
					     float *pattern_errors,
					     float zero_epsilon_distance,
					     unsigned int max_x,
					     unsigned int lda_x,
					     unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float d = output[index] - target_output[index];
    if (fabsf(d) < zero_epsilon_distance) d = 0.0f;
    pattern_errors[index] = d*d;
  }
}

__global__ void computeMSEGradientKernel(const float *output,
					 const float *target_output,
					 float *error_output,
					 float zero_epsilon_distance,
					 unsigned int max_x,
					 unsigned int lda_x,
					 unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float d = output[index] - target_output[index];
    if (fabsf(d) < zero_epsilon_distance) d = 0.0f;
    error_output[index] = d;
  }
}

__global__ void computeMAELossFunctionKernel(const float *output,
					     const float *target_output,
					     float *pattern_errors,
					     float zero_epsilon_distance,
					     unsigned int max_x,
					     unsigned int lda_x,
					     unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float absd = fabsf(output[index] - target_output[index]);
    if (absd < zero_epsilon_distance) absd = 0.0f;
    pattern_errors[index] = absd;
  }
}

__global__ void computeMAEGradientKernel(const float *output,
					 const float *target_output,
					 float *error_output,
					 float zero_epsilon_distance,
					 unsigned int max_x,
					 unsigned int lda_x,
					 unsigned int max_y,
					 float invN) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float d = output[index] - target_output[index];
    if (fabsf(d) < zero_epsilon_distance) error_output[index] = 0.0f;
    else {
      if (d < 0.0f) error_output[index] = -invN;
      else error_output[index] = invN;
    }
  }
}

__global__ void computeMultiClassCrossEntropyLossFunctionKernel(const float *output,
								const float *target_output,
								float *pattern_errors,
								float epsilon,
								unsigned int max_x,
								unsigned int lda_x,
								unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    // compute derivative
    // float o = clip(output[index], inf, epsilon, 1.0f - epsilon);
    float log_o = output[index];
    float t = clip(target_output[index], epsilon, 1.0f - epsilon);
    if (t > epsilon) pattern_errors[index] = t * log_o;
    else pattern_errors[index] = 0.0f;
  }
}

__global__ void computeCrossEntropyLossFunctionKernel(const float *output,
						      const float *target_output,
						      float *pattern_errors,
						      float epsilon,
						      unsigned int max_x,
						      unsigned int lda_x,
						      unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    // compute derivative
    float  log_o     = clip(output[index], logf(epsilon), logf(1.0 - epsilon));
    double o         = exp(log_o);
    float  log_inv_o = log(1.0 - o);
    float  t         = clip(target_output[index], epsilon, 1.0f - epsilon);
    float  inv_t     = clip(1.0f - target_output[index], epsilon, 1.0f - epsilon);
    if (t > epsilon) pattern_errors[index] = t * log_o;
    else pattern_errors[index] = 0.0f;
    if (inv_t > epsilon) pattern_errors[index] += inv_t * log_inv_o;
  }
}

__global__ void computeCrossEntropyGradientKernel(const float *output,
						  const float *target_output,
						  float *error_output,
						  float zero,
						  unsigned int max_x,
						  unsigned int lda_x,
						  unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    // compute derivative
    float v = clip(output[index], logf(zero), logf(1.0 - zero));
    error_output[index] = expf(v) - target_output[index];
  }
}

__global__ void applyTanhErrorFunctionKernel(const float *output,
					     const float *target_output,
					     float *output_error,
					     float *pattern_errors,
					     unsigned int max_x,
					     unsigned int lda_x,
					     unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float d = output_error[index] = output[index] - target_output[index];
    if (d < -0.9999999f)
      output_error[index] = -DERIVATIVE_SATURATION;
    else if (d > 0.9999999f)
      output_error[index] =  DERIVATIVE_SATURATION;
    else output_error[index] = log((1.0f+output_error[index])/(1.0f-output_error[index]));
    pattern_errors[index] = d*d;
  }
}

template<typename T>
void sumBunchPatternErrors(GPUMirroredMemoryBlock<T> *loss_output,
			   const GPUMirroredMemoryBlock<T> *pattern_errors,
			   unsigned int bunch_size, unsigned int size) {
  for (unsigned int i=0; i<bunch_size; ++i) {
    doSum(size, pattern_errors, bunch_size, i, true, T(),
          loss_output, i);
  }
}

#endif


///////////////////////////////////////////////////////////
///////////////// Error functions wrappers ////////////////
///////////////////////////////////////////////////////////

/**
 * Generic template for expansion of loss functions code which are computed as a
 * sum of the loss for every position of input/target matrices. The sum is
 * computed in two loops, and traversing in col-major (first by bunch_size).
 * The first loop computes the loss of the first component of all the patterns,
 * and stores it at the loss_output_ptr. The second loop computes the loss of
 * the rest of components, adding it to the loss_output_ptr. The parameters of
 * the template are:
 *
 * @param[in]  input - A FloatGPUMirroredMemoryBlock pointer.
 * @param[in]  target - A FloatGPUMirroredMemoryBlock pointer.
 * @param[out] loss_output - A FloatGPUMirroredMemoryBlock pointer.
 * @param[in]  size - The number of components in one pattern.
 * @param[in]  bunch_size - The number of patterns.
 * @param[in]  func - The function which will be executed, it receives an input pattern, an output pattern and the zero value.
 * @param[in]  zero - The value of zero.
 */
template<typename F, typename T>
void COMPUTE_LOSS(FloatGPUMirroredMemoryBlock *input,
		  FloatGPUMirroredMemoryBlock *target,
		  FloatGPUMirroredMemoryBlock *loss_output,
		  unsigned int size,
		  unsigned int bunch_size,
		  F func, T zero) {
  const float *input_ptr  = (input)->getPPALForRead();
  const float *target_ptr = (target)->getPPALForRead();
  float *loss_output_ptr  = (loss_output)->getPPALForWrite();
  for (unsigned int b=0; b<(bunch_size); ++b) {
    float var = func(input_ptr[b], target_ptr[b], zero);
    loss_output_ptr[b] = var;
  }
  input_ptr  += bunch_size;
  target_ptr += bunch_size;
  for (unsigned int i = 1; i < (size); i++) {
    for (unsigned int b=0; b<(bunch_size); ++b) {
      float var = func(input_ptr[b], target_ptr[b], zero);
      loss_output_ptr[b] += var;
    }
    input_ptr  += bunch_size;
    target_ptr += bunch_size;
  }
}

float MSE(float input, float target, float zero) {
  float d = input - target;
  if (fabs(d) < zero) d = 0.0f;
  else d = d*d;
  return d;
}
void doMSELossFunction(FloatGPUMirroredMemoryBlock *input,
		       FloatGPUMirroredMemoryBlock *target,
		       FloatGPUMirroredMemoryBlock *loss_output,
		       float zero_epsilon_distance,
		       unsigned int size,
		       unsigned int bunch_size,
		       bool use_gpu) {
#ifndef USE_CUDA
  UNUSED_VARIABLE(use_gpu);
#endif
#ifdef USE_CUDA
  if (use_gpu) {
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    FloatGPUMirroredMemoryBlock *pattern_errors =
      new FloatGPUMirroredMemoryBlock(target->getSize());
    float *pattern_errors_ptr = pattern_errors->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMSELossFunctionKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       pattern_errors_ptr,
       zero_epsilon_distance,
       bunch_size,
       bunch_size,
       size);
    sumBunchPatternErrors(loss_output,
			  pattern_errors,
			  bunch_size, size);
    printf("WRAPPER %f %f %f %f :: %f %f\n",
           pattern_errors->get(0),
           pattern_errors->get(1),
           pattern_errors->get(2),
           pattern_errors->get(3),
           loss_output->get(0),
           loss_output->get(1));
    delete pattern_errors;
  }
  else {
#endif
    COMPUTE_LOSS(input,target,loss_output,size,bunch_size,MSE,
		 zero_epsilon_distance);
#ifdef USE_CUDA
  }
#endif
}


void doComputeMSEGradient(FloatGPUMirroredMemoryBlock *input,
			  FloatGPUMirroredMemoryBlock *target,
			  FloatGPUMirroredMemoryBlock *error_output,
			  float zero_epsilon_distance,
			  unsigned int size,
			  unsigned int bunch_size,
			  bool use_gpu) {
#ifndef USE_CUDA
  UNUSED_VARIABLE(use_gpu);
#endif
#ifdef USE_CUDA
  if (use_gpu) {
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    float *error_output_ptr = error_output->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMSEGradientKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       error_output_ptr,
       zero_epsilon_distance,
       bunch_size,
       bunch_size,
       size);
  }
  else {
#endif
    float d = 0.0f;
    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    float *error_output_ptr = error_output->getPPALForWrite();
    for (unsigned int i = 0; i < size; i++) {
      for (unsigned int b=0; b<bunch_size; ++b) {
	d = input_ptr[b] - target_ptr[b];
	if (fabsf(d) < zero_epsilon_distance) d = 0.0f;
	error_output_ptr[b] = d;
      }
      input_ptr  += bunch_size;
      target_ptr += bunch_size;
      error_output_ptr += bunch_size;
    }
#ifdef USE_CUDA
  }
#endif
}

float MAE(float input, float target, float zero) {
  float absd = fabsf(input - target);
  if (absd < zero) absd = 0.0f;
  return absd;
}
void doMAELossFunction(FloatGPUMirroredMemoryBlock *input,
		       FloatGPUMirroredMemoryBlock *target,
		       FloatGPUMirroredMemoryBlock *loss_output,
		       float zero_epsilon_distance,
		       unsigned int size,
		       unsigned int bunch_size,
		       bool use_gpu) {
#ifndef USE_CUDA
  UNUSED_VARIABLE(use_gpu);
#endif
#ifdef USE_CUDA
  if (use_gpu) {
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    FloatGPUMirroredMemoryBlock *pattern_errors =
      new FloatGPUMirroredMemoryBlock(target->getSize());
    float *pattern_errors_ptr = pattern_errors->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMAELossFunctionKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       pattern_errors_ptr,
       zero_epsilon_distance,
       bunch_size,
       bunch_size,
       size);
    sumBunchPatternErrors(loss_output,
			  pattern_errors,
			  bunch_size, size);
    delete pattern_errors;
  }
  else {
#endif

    COMPUTE_LOSS(input,target,loss_output,size,bunch_size,
		 MAE, zero_epsilon_distance);

#ifdef USE_CUDA
  }
#endif
}


void doComputeMAEGradient(FloatGPUMirroredMemoryBlock *input,
			  FloatGPUMirroredMemoryBlock *target,
			  FloatGPUMirroredMemoryBlock *error_output,
			  float zero_epsilon_distance,
			  unsigned int size,
			  unsigned int bunch_size,
			  bool use_gpu) {
#ifndef USE_CUDA
  UNUSED_VARIABLE(use_gpu);
#endif
#ifdef USE_CUDA
  if (use_gpu) {
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    float *error_output_ptr = error_output->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMAEGradientKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       error_output_ptr,
       zero_epsilon_distance,
       bunch_size,
       bunch_size,
       size,
       1.0f/size);
  }
  else {
#endif
    float d = 0.0f;
    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    float *error_output_ptr = error_output->getPPALForWrite();
    float invN = 1.0f/size;
    for (unsigned int i = 0; i < size; i++) {
      for (unsigned int b=0; b<bunch_size; ++b) {
	d = input_ptr[b] - target_ptr[b];
	if (fabsf(d) < zero_epsilon_distance) error_output_ptr[b] = 0.0f;
	else {
	  if (d < 0.0f) error_output_ptr[b] = -invN;
	  else error_output_ptr[b] = invN;
	}
      }
      input_ptr  += bunch_size;
      target_ptr += bunch_size;
      error_output_ptr += bunch_size;
    }
#ifdef USE_CUDA
  }
#endif
}

struct CEData {
  float log_epsilon, log_1_epsilon, EPSILON;
};
float CE(float input, float target, CEData data) {
  float log_epsilon   = data.log_epsilon;
  float log_1_epsilon = data.log_1_epsilon;
  float EPSILON       = data.EPSILON;
  april_assert(!(input > 0.0f) &&
	       "Only log-based activation functions are allowed");
  april_assert(!(target < 0.0f) && !(target > 1.0f) &&
	       "Only [0,1] target patterns are allowed");
  // compute derivative
  float  log_o     = clamp(input, log_epsilon, log_1_epsilon);
  double o         = exp(log_o);
  float  log_inv_o = log(1.0 - o);
  // CLAMP of reference (target)
  float  t         = clamp(target, EPSILON, 1.0f - EPSILON);
  // CLAMP of 1.0 - reference (target). We do clamp again to avoid
  // numerical approximation problems, and to ensure correct working of
  // inv_t > EPSILON comparison
  float  inv_t     = clamp(1.0f - target, EPSILON, 1.0f - EPSILON);
  // printf("%g * %g + %g * %g :: %g\n", t, log_o, inv_t, log_inv_o, o);
  float sum;
  if (t > EPSILON) sum = -t * log_o;
  else sum = 0.0f;
  if (inv_t > EPSILON) sum -= inv_t * log_inv_o;
  return sum;
}
void doCrossEntropyLossFunction(FloatGPUMirroredMemoryBlock *input,
				FloatGPUMirroredMemoryBlock *target,
				FloatGPUMirroredMemoryBlock *loss_output,
				float EPSILON,
				unsigned int size,
				unsigned int bunch_size,
				bool use_gpu) {
#ifndef USE_CUDA
  UNUSED_VARIABLE(use_gpu);
#endif
#ifdef USE_CUDA
  if (use_gpu) {
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    FloatGPUMirroredMemoryBlock *pattern_errors =
      new FloatGPUMirroredMemoryBlock(target->getSize());
    float *pattern_errors_ptr = pattern_errors->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeCrossEntropyLossFunctionKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       pattern_errors_ptr,
       EPSILON,
       bunch_size,
       bunch_size,
       size);
    sumBunchPatternErrors(loss_output,
			  pattern_errors,
			  bunch_size, size);
    delete pattern_errors;
  }
  else {
#endif
    CEData ce_data = { logf(EPSILON), logf(1.0f - EPSILON), EPSILON };
    COMPUTE_LOSS(input,target,loss_output,size,bunch_size,
		 CE, ce_data);
#ifdef USE_CUDA
  }
#endif
}

float MultiClassCE(float input, float target, float EPSILON) {
  april_assert(!(input > 0.0f) &&
	       "Only log-based activation functions are allowed");
  april_assert((!(target < 0.0f)) && (!(target > 1.0f)) &&
	       "Only [0,1] target patterns are allowed");
  // compute derivative
  float log_o = input;
  float t = clamp(target, EPSILON, 1.0f - EPSILON);
  float sum;
  if (t > EPSILON) sum = -t * log_o;
  else sum = 0.0f;
  return sum;
}
void doMultiClassCrossEntropyLossFunction(FloatGPUMirroredMemoryBlock *input,
					  FloatGPUMirroredMemoryBlock *target,
					  FloatGPUMirroredMemoryBlock *loss_output,
					  float EPSILON,
					  unsigned int size,
					  unsigned int bunch_size,
					  bool use_gpu) {
#ifndef USE_CUDA
  UNUSED_VARIABLE(use_gpu);
#endif
#ifdef USE_CUDA
  if (use_gpu) {
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    FloatGPUMirroredMemoryBlock *pattern_errors =
      new FloatGPUMirroredMemoryBlock(target->getSize());
    float *pattern_errors_ptr = pattern_errors->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMultiClassCrossEntropyLossFunctionKernel<<<grid, block, 0,
      GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       pattern_errors_ptr,
       EPSILON,
       bunch_size,
       bunch_size,
       size);
    sumBunchPatternErrors(loss_output,
			  pattern_errors,
			  bunch_size, size);
    delete pattern_errors;
  }
  else {
#endif
    COMPUTE_LOSS(input,target,loss_output,size,bunch_size,
		 MultiClassCE, EPSILON);
#ifdef USE_CUDA
  }
#endif
}

void doComputeCrossEntropyGradient(FloatGPUMirroredMemoryBlock *input,
				   FloatGPUMirroredMemoryBlock *target,
				   FloatGPUMirroredMemoryBlock *error_output,
				   float EPSILON,
				   unsigned int size,
				   unsigned int bunch_size,
				   bool use_gpu) {
#ifndef USE_CUDA
  UNUSED_VARIABLE(use_gpu);
#endif
#ifdef USE_CUDA
  if (use_gpu) {
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    float *error_output_ptr = error_output->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeCrossEntropyGradientKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       error_output_ptr,
       EPSILON,
       bunch_size,
       bunch_size,
       size);
  }
  else {
#endif
    float log_epsilon   = logf(EPSILON);
    float log_1_epsilon = logf(1.0f - EPSILON);

    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    float *error_output_ptr = error_output->getPPALForWrite();
    for (unsigned int i = 0; i < size; i++) {
      for (unsigned int b=0; b<bunch_size; ++b)
	error_output_ptr[b] =
	  expf(clamp(input_ptr[b], log_epsilon, log_1_epsilon)) - target_ptr[b];
      input_ptr  += bunch_size;
      target_ptr += bunch_size;
      error_output_ptr += bunch_size;
    }
#ifdef USE_CUDA
  }
#endif
}

/*
  void doCalculateTanhErrorFunction(FloatGPUMirroredMemoryBlock *output,
  FloatGPUMirroredMemoryBlock *target_output,
  FloatGPUMirroredMemoryBlock *output_error,
  FloatGPUMirroredMemoryBlock *pattern_errors,
  unsigned int output_size,
  const ANNConfiguration &conf,
  bool use_gpu) {
  #ifdef USE_CUDA
  if (use_gpu) {
  const float *output_ptr        = output->getGPUForRead();
  const float *target_output_ptr = target_output->getGPUForRead();
  float *output_error_ptr        = output_error->getGPUForWrite();
  float *pattern_errors_ptr      = pattern_errors->getGPUForWrite();
  dim3 block, grid;
  computeBlockAndGridSizesForAColumnMajorBunch(conf, output_size,
  block, grid);

  applyTanhErrorFunctionKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
  (output_ptr,
  target_output_ptr,
  output_error_ptr,
  pattern_errors_ptr,
  conf.cur_bunch_size,
  conf.max_bunch_size,
  output_size);
  }
  else {
  #endif
  float d = 0;
  const float *output_ptr        = output->getPPALForRead();
  const float *target_output_ptr = target_output->getPPALForRead();
  float *output_error_ptr        = output_error->getPPALForWrite();
  float *pattern_errors_ptr      = pattern_errors->getPPALForWrite();

  for (unsigned int i = 0; i < output_size; i++) {
  for (unsigned int b=0; b<conf.cur_bunch_size; ++b) {
  d = output_error_ptr[b] = output_ptr[b] - target_output_ptr[b];
  if (d < -0.9999999f)
  output_error_ptr[b] = -DERIVATIVE_SATURATION;
  else if (d > 0.9999999f)
  output_error_ptr[b] =  DERIVATIVE_SATURATION;
  else output_error_ptr[b] = log((1.0f+output_error_ptr[b])/(1.0f-output_error_ptr[b]));
  pattern_errors_ptr[b] += d*d;
  }
  output_ptr         += conf.max_bunch_size;
  target_output_ptr  += conf.max_bunch_size;
  output_error_ptr   += conf.max_bunch_size;
  pattern_errors_ptr += conf.max_bunch_size;
  }
  #ifdef USE_CUDA
  }
  #endif
  }
*/

/*
  void doCalculateMixtureCrossEntropy(FloatGPUMirroredMemoryBlock *output,
  FloatGPUMirroredMemoryBlock *target_output,
  FloatGPUMirroredMemoryBlock *output_error,
  FloatGPUMirroredMemoryBlock *pattern_errors,
  float EPSILON,
  float INF,
  unsigned int output_size,
  const ANNConfiguration &conf,
  bool use_gpu) {
  const float *output_ptr        = output->getPPALForRead();
  const float *target_output_ptr = target_output->getPPALForRead();
  float *output_error_ptr        = output_error->getPPALForWrite();
  float *pattern_errors_ptr      = pattern_errors->getGPUForWrite();

  for (unsigned int b=0; b<conf.cur_bunch_size; ++b) {
  float Z = 0.0f;
  unsigned int ipos = b;
  for (unsigned int i=0; i<output_size; ++i)
  {
  Z += target_output_ptr[ipos] * output_ptr[ipos];
  ipos += conf.max_bunch_size;
  }
  Z = 1.0f/Z;
  float prob = 0.0f;
  ipos = b;
  for (unsigned int i = 0; i < output_size; i++) {
  float component_prob = target_output_ptr[ipos] * output_ptr[ipos];
  output_error_ptr[ipos] = output_ptr[ipos] - component_prob*Z;
  prob += component_prob;
  ipos += conf.max_bunch_size;
  }
  s += ((fabs(prob) > EPSILON) ? logf(prob) : INF);
  }
  return s;
  }
*/

/*
  void doCalculateGA(FloatGPUMirroredMemoryBlock *output,
  FloatGPUMirroredMemoryBlock *target_output,
  FloatGPUMirroredMemoryBlock *output_error,
  FloatGPUMirroredMemoryBlock *pattern_errors,
  unsigned int output_size,
  const ANNConfiguration &conf,
  bool use_gpu) {
  const float *output_ptr        = output->getPPALForRead();
  const float *target_output_ptr = target_output->getPPALForRead();
  float *output_error_ptr        = output_error->getPPALForWrite();

  for (unsigned int b=0; b<conf.cur_bunch_size; ++b) {
  // Las 2 siguientes variables no se emplean?
  //float sum_a_b = 0.0f;
  //float sum_c_a_b;
  float Gab = 0.0f, Hab = 0.0f;
  unsigned int ipos = b;
  for (unsigned int i = 0; i < output_size; i++) {
  Gab += output_ptr[ipos] * target_output_ptr[ipos];
  Hab += output_ptr[ipos] + target_output_ptr[ipos];
  ipos += conf.max_bunch_size;
  }
  Gab *= 2.0f;
  s   += 1.0f - Gab/Hab; // hacemos 1 - FMeasure para cambiar la minimizacion
  // por una maximizacion
  float HabP2 = Hab*Hab;
  ipos = b;
  for (unsigned int i = 0; i < output_size; i++) {
  // Aqui cambiamos de signo para convertir una minimizacion en una
  // maximizacion
  output_error_ptr[ipos] = -(2 * target_output_ptr[ipos] * Hab - Gab) / HabP2;
  ipos += conf.max_bunch_size;
  }
  }
  return s;
  }

*/

} // namespace AprilMath

#undef sigmoid
#undef clip
