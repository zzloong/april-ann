/*
 * This file is part of APRIL-ANN toolkit (A
 * Pattern Recognizer In Lua with Artificial Neural Networks).
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
#include "unused_variable.h"
#include "swap.h"
#include "dot_product_component.h"
#include "wrapper.h"
#include "token_base.h"
#include "token_vector.h"
#include "table_of_token_codes.h"

using april_utils::swap;

namespace ANN {

  ///////////////////////////////////////////
  // DotProductANNComponent implementation //
  ///////////////////////////////////////////
  
  DotProductANNComponent::DotProductANNComponent(const char *name,
						 const char *weights_name,
						 unsigned int input_size,
						 unsigned int output_size,
						 bool transpose_weights) :
    ANNComponent(name, weights_name, input_size, output_size),
    input(0),
    error_input(0),
    output(0),
    error_output(0),
    weights_matrix(0) {
    if (weights_name == 0) generateDefaultWeightsName(this->weights_name, "w");
    this->transpose_weights = (transpose_weights) ? CblasTrans : CblasNoTrans;
  }
  
  DotProductANNComponent::~DotProductANNComponent() {
    if (weights_matrix) DecRef(weights_matrix);
    if (input) DecRef(input);
    if (error_input) DecRef(error_input);
    if (output) DecRef(output);
    if (error_output) DecRef(error_output);
  }
  
  // The DotProductANNComponent
  Token *DotProductANNComponent::doForward(Token *_input, bool during_training) {
    UNUSED_VARIABLE(during_training);
    if (weights_matrix == 0) ERROR_EXIT1(129, "Not built component %s\n",
					 name.c_str());
    MatrixFloat *weights_mat = weights_matrix->getPtr();
    // error checking
    if (_input == 0) ERROR_EXIT1(129,"Null Token received! [%s]\n",
				 name.c_str());
    // Three tokens are allowed: matrix, sparse, vector of sparse
    switch(_input->getTokenCode()) {
    case table_of_token_codes::token_matrix: {
      sparse_input = false;
      // change current input by new input
      AssignRef(input,_input);
      TokenMatrixFloat *input_mat_token=input->convertTo<TokenMatrixFloat*>();
      MatrixFloat *input_mat=input_mat_token->getMatrix();
      ASSERT_MATRIX(input_mat);
      april_assert(input_mat->getDimSize(1) == static_cast<int>(input_size));
      if (input_mat->getStrideSize(0) > 1) {
	input_mat = input_mat->clone();
	AssignRef(input,new TokenMatrixFloat(input_mat));
      }
#ifdef USE_CUDA
      input_mat->setUseCuda(use_cuda);
#endif
      unsigned int bunch_size = input_mat->getDimSize(0);
      // new output to fit the bunch
      MatrixFloat *output_mat;
      int dims[2] = { static_cast<int>(bunch_size),
		      static_cast<int>(output_size) };
      output_mat = new MatrixFloat(2, dims, CblasColMajor);
      AssignRef(output,new TokenMatrixFloat(output_mat));
#ifdef USE_CUDA
      output_mat->setUseCuda(use_cuda);
#endif
      if (bunch_size == 1) {
	// vector x matrix product
	output_mat->gemv(transpose_weights,
			 1.0f, weights_mat,
			 input_mat,
			 0.0f);
      } // if bunch_size==1
      else {
	// matrix x matrix product
	// C = \alpha op(A) op(B) + \beta C
	// input * weights = output
	output_mat->gemm(CblasNoTrans,
			 NEGATE_CBLAS_TRANSPOSE(transpose_weights),
			 1.0f, input_mat, weights_mat,
			 0.0f);
      } // if bunch_size==1 ... else
      break;
    }
    case table_of_token_codes::vector_float_sparse: {
      TokenBunchVector *aux = new TokenBunchVector();
      aux->push_back(_input);
      _input = aux; // is not necessary to do incref(aux) or decref(_input)
      // the incref is done at line 127
      
      // continues in the next case
    }
    case table_of_token_codes::vector_Tokens: {
      sparse_input = true;
      AssignRef(input, _input);
      TokenBunchVector *input_vector_token=input->convertTo<TokenBunchVector*>();
      april_assert(input_vector_token->size() > 0);
      // new output to fit the bunch
      MatrixFloat *output_mat;
      int dims[2] = {static_cast<int>(input_vector_token->size()),
		     static_cast<int>(output_size)};
      output_mat = new MatrixFloat(2, dims, CblasColMajor);
      AssignRef(output,new TokenMatrixFloat(output_mat));
#ifdef USE_CUDA
      output_mat->setUseCuda(use_cuda);
#endif      
      output_mat->zeros();
      
      // dimension for select operation
      int w_dim = (transpose_weights == CblasNoTrans) ? 1 : 0;
      for (unsigned int b=0; b<input_vector_token->size(); ++b) {
	MatrixFloat *output_pat_mat = output_mat->select(0,static_cast<int>(b));
	Token *current = (*input_vector_token)[b];
	if (current->getTokenCode()!=table_of_token_codes::vector_float_sparse)
	  ERROR_EXIT1(128,"Incorrect token type, expected vector_float_sparse [%s]\n",
		      name.c_str());
	TokenSparseVectorFloat *sparse_token;
	sparse_token = current->convertTo<TokenSparseVectorFloat*>();
	for (unsigned int k=0; k<sparse_token->size(); ++k) {
	  unsigned int pos     = (*sparse_token)[k].first;
	  float value          = (*sparse_token)[k].second;
	  int w_index          = static_cast<int>(pos);
	  if (pos >= input_size)
	    ERROR_EXIT1(128, "Overflow at sparse vector input pos [%s]\n",
			name.c_str());
	  MatrixFloat *w_column = weights_mat->select(w_dim, w_index);
	  output_pat_mat->axpy(value, w_column);
	  delete w_column;
	}
	delete output_pat_mat;
      }
      break;
    }
    default:
      ERROR_EXIT2(128, "Incorrect token type: %d [%s]\n", _input->getTokenCode(),
		  name.c_str());
    };
    return output;
  }
  
  Token *DotProductANNComponent::doBackprop(Token *_error_input) {
    // error checking
    if ( (_error_input == 0) ||
	 (_error_input->getTokenCode() != table_of_token_codes::token_matrix))
      ERROR_EXIT1(129,"Incorrect input error Token type, expected token_matrix! [%s]\n",
		  name.c_str());
    // change current input by new input
    AssignRef(error_input,_error_input->convertTo<TokenMatrixFloat*>());
    if (sparse_input) {
      // If input is sparse, the component needs to be an input of the ANN,
      // therefore the input is probably SO LARGE, and computing the backprop
      // will lead in HIGH computational cost ;) Because of this, the components
      // returns a NULL gradient pointer
      if (error_output) { DecRef(error_output); error_output = 0; }
      return 0;
    }
    MatrixFloat *error_input_mat = error_input->getMatrix();
    if (! error_input_mat->sameDim(output->getMatrix()) )
      ERROR_EXIT1(129, "Different bunches found at doForward and doBackprop [%s]\n",
		  name.c_str());
    // new error output to fit the bunch
    ASSERT_MATRIX(error_input_mat);
    april_assert(error_input_mat->getDimSize(1) == static_cast<int>(output_size));
    if (error_input_mat->getStrideSize(0) > 1) {
      error_input_mat = error_input_mat->clone();
      AssignRef(error_input,new TokenMatrixFloat(error_input_mat));
    }
#ifdef USE_CUDA
    error_input_mat->setUseCuda(use_cuda);
#endif
    unsigned int bunch_size = error_input_mat->getDimSize(0);
    // new output to fit the bunch
    MatrixFloat *error_output_mat;
    int dims[2] = { static_cast<int>(bunch_size),
		    static_cast<int>(input_size) };
    error_output_mat = new MatrixFloat(2, dims, CblasColMajor);
    AssignRef(error_output,new TokenMatrixFloat(error_output_mat));
#ifdef USE_CUDA
    error_output_mat->setUseCuda(use_cuda);
#endif      
    //
    MatrixFloat *weights_mat = weights_matrix->getPtr();
    if (bunch_size > 1) {
      // C = alpha * A * B + beta * C
      error_output_mat->gemm(CblasNoTrans, transpose_weights,
			     1.0f, error_input_mat,
			     weights_mat,
			     0.0f);
    }
    else {
      error_output_mat->gemv(NEGATE_CBLAS_TRANSPOSE(transpose_weights),
			     1.0f, weights_mat,
			     error_input_mat,
			     0.0f);
    }
    return error_output;
  }
  
  void DotProductANNComponent::computeGradients(MatrixFloat*& grads_mat) {
    weights_matrix->addToSharedCount();
    if (grads_mat == 0) {
      grads_mat = weights_matrix->getPtr()->cloneOnlyDims();
      grads_mat->zeros();
    }
    else if (!grads_mat->sameDim(weights_matrix->getPtr()))
      ERROR_EXIT(128, "Incorrect weights matrix dimensions\n");
    MatrixFloat *error_input_mat = error_input->getMatrix();
    unsigned int bunch_size = error_input_mat->getDimSize(0);
    if (sparse_input) {
      TokenBunchVector *input_vector_token;
      input_vector_token  = input->convertTo<TokenBunchVector*>();
      int w_dim = (transpose_weights == CblasNoTrans) ? 1 : 0;
      for (unsigned int b=0; b<bunch_size; ++b) {
	MatrixFloat *error_input_pat_mat;
	error_input_pat_mat = error_input_mat->select(0,static_cast<int>(b));
	Token *current = (*input_vector_token)[b];
	TokenSparseVectorFloat *sparse_token;
	sparse_token = current->convertTo<TokenSparseVectorFloat*>();
	for (unsigned int k=0; k<sparse_token->size(); ++k) {
	  unsigned int pos     = (*sparse_token)[k].first;
	  float value          = (*sparse_token)[k].second;
	  int w_index          = static_cast<int>(pos);
	  if (pos >= input_size)
	    ERROR_EXIT1(128, "Overflow at sparse vector input pos [%s]\n",
			name.c_str());
	  MatrixFloat *w_column = grads_mat->select(w_dim, w_index);
	  w_column->axpy(value, error_input_pat_mat);
	  delete w_column;
	}
	delete error_input_pat_mat;
      }
    } // if sparse_input ... else
    else {
      TokenMatrixFloat *input_mat_token=input->convertTo<TokenMatrixFloat*>();
      MatrixFloat *input_mat=input_mat_token->getMatrix();
      if (bunch_size > 1) {
	grads_mat->gemm(CblasTrans, CblasNoTrans,
			1.0f,
			(transpose_weights == CblasNoTrans)?error_input_mat:input_mat, // A
			(transpose_weights == CblasNoTrans)?input_mat:error_input_mat, // B
			1.0f);
      } // if bunch_size > 1 ... else
      else {
	grads_mat->ger(1.0f,
		       (transpose_weights == CblasNoTrans)?error_input_mat:input_mat,
		       (transpose_weights == CblasNoTrans)?input_mat:error_input_mat);
      } // if bunch_size > 1 ... else
    } // if sparse_input ... else
  }

  void DotProductANNComponent::reset() {
    if (input)        DecRef(input);
    if (error_input)  DecRef(error_input);
    if (output)       DecRef(output);
    if (error_output) DecRef(error_output);
    input	 = 0;
    error_input	 = 0;
    output	 = 0;
    error_output = 0;
    weights_matrix->resetSharedCount();
  }
  
  ANNComponent *DotProductANNComponent::clone() {
    DotProductANNComponent *component = new
      DotProductANNComponent(name.c_str(), weights_name.c_str(),
			     input_size, output_size,
			     (transpose_weights == CblasTrans));
    component->input_size     = input_size;
    component->output_size    = output_size;
    return component;
  }
  
  void DotProductANNComponent::build(unsigned int _input_size,
				     unsigned int _output_size,
				     hash<string,Connections*> &weights_dict,
				     hash<string,ANNComponent*> &components_dict) {
    ANNComponent::build(_input_size, _output_size,
			weights_dict, components_dict);
    //
    if (input_size == 0 || output_size == 0)
      ERROR_EXIT1(141, "Impossible to compute input/output "
		  "sizes for this component [%s]\n",
		  name.c_str());
    unsigned int weights_input_size  = input_size;;
    unsigned int weights_output_size = output_size;
    ////////////////////////////////////////////////////////////////////
    if (transpose_weights == CblasTrans)
      swap(weights_input_size, weights_output_size);
    Connections *&w = weights_dict[weights_name];
    // printf("%s :: %p %p\n", weights_name.c_str(), w, weights_matrix);
    if (w != 0) {
      // printf("COPY OF WEIGHTS FROM HASH %s\n", weights_name.c_str());
      AssignRef(weights_matrix, w);
      if (!weights_matrix->checkInputOutputSizes(weights_input_size,
						 weights_output_size))
	ERROR_EXIT3(256,"The weights matrix input/output sizes are not correct, "
		    "expected %dx%d [%s]\n",
		    weights_input_size, weights_output_size,
		    name.c_str());
    }
    else {
      if (weights_matrix == 0) {
	// printf("NEW OF WEIGHTS %s\n", weights_name.c_str());
	weights_matrix = new Connections(weights_input_size,
					 weights_output_size);
	IncRef(weights_matrix);
      }
      // else printf("USING PREVIOUS WEIGHTS %s\n", weights_name.c_str());
      w = weights_matrix;
    }
  }

  void DotProductANNComponent::copyWeights(hash<string,Connections*> &weights_dict) {
    if (weights_matrix == 0)
      ERROR_EXIT1(100, "Component not built, impossible execute copyWeights [%s]\n",
		  name.c_str());
    Connections *&w = weights_dict[weights_name];
    if (w != 0 && w != weights_matrix)
      ERROR_EXIT2(101, "Weights dictionary contains %s weights name which is "
		  "not shared with weights_matrix attribute [%s]\n",
		  weights_name.c_str(),
		  name.c_str());
    else if (w == 0) w = weights_matrix;
  }  

  char *DotProductANNComponent::toLuaString() {
    buffer_list buffer;
    buffer.printf("ann.components.dot_product{ name='%s',weights='%s',"
		  "input=%d,output=%d,transpose=%s }",
		  name.c_str(), weights_name.c_str(),
		  input_size, output_size,
		  (transpose_weights==CblasTrans)?"true":"false");
    return buffer.to_string(buffer_list::NULL_TERMINATED);
  }
  //////////////////////////////////////////////////////////////////////////
}