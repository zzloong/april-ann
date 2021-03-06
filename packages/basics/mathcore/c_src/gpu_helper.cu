/*
 * This file is part of the Neural Network modules of the APRIL toolkit (A
 * Pattern Recognizer In Lua).
 *
 * Copyright 2012, Salvador España-Boquera, Adrian Palacios Corella, Francisco
 * Zamora-Martinez
 *
 * The APRIL-MLP toolkit is free software; you can redistribute it and/or modify it
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
#include "gpu_helper.h"

#ifdef USE_CUDA
namespace AprilMath {
  namespace CUDA {

    bool GPUHelper::initialized = false;
    cublasHandle_t GPUHelper::handler;
    cusparseHandle_t GPUHelper::sparse_handler;
    cudaDeviceProp GPUHelper::properties;
    CUdevice GPUHelper::device;
    CUcontext GPUHelper::context;
    AprilUtils::vector<CUstream> GPUHelper::streams;
    unsigned int GPUHelper::current_stream = 0;

  } // namespace CUDA
} // namespace AprilMath
#endif
