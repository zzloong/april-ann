/*
 * This file is part of APRIL-ANN toolkit (A
 * Pattern Recognizer In Lua with Artificial Neural Networks).
 *
 * Copyright 2013, Francisco Zamora-Martinez
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
#ifndef REDUCE_SPARSE_MATRIX_IMPL_CU
#define REDUCE_SPARSE_MATRIX_IMPL_CU

#include "matrix.h"
#include "reduce_sparse_matrix.h"
#include "reduce_template.h"

namespace AprilMath {
  
  namespace MatrixExt {
  
    template<typename T, typename O, typename OP>
    O SparseMatrixScalarReduce1(const Basics::SparseMatrix<T> *input,
                                const OP &scalar_red_functor,
                                const O &zero) {
      return genericReduceCall(input->nonZeroSize(),
                               input->getRawValuesAccess(), 1u, 0u,
                               input->getCudaFlag(),
                               zero,
                               scalar_red_functor);
    }

  } // namespace MatrixExt
  
} // namespace AprilMath

#endif // REDUCE_SPARSE_MATRIX_H
