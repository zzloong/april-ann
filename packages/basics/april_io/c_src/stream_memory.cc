/*
 * This file is part of APRIL-ANN toolkit (A
 * Pattern Recognizer In Lua with Artificial Neural Networks).
 *
 * Copyright 2014, Francisco Zamora-Martinez
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

#include <cstdarg>
#include "stream_memory.h"
#include "unused_variable.h"

namespace april_io {
  
  size_t extractLineFromStream(Stream *source, StreamMemory *dest) {
    return source->get(dest, "\n\r");
  }

  size_t extractULineFromStream(Stream *source, StreamMemory *dest) {
    do {
      dest->clear();
      source->get(dest, "\n\r");
    } while ((dest->size() > 0) && ((*dest)[0] == '#'));
    return dest->size();
  }

  ///////////////////////////////////////////////////////////////////////////
  
  StreamMemory::StreamMemory(size_t block_size, size_t max_size) :
    block_size(block_size), max_size(max_size),
    in_block(0), in_block_len(0),
    out_block(0), out_block_len(0) {
  }
  
  StreamMemory::~StreamMemory() {
    close();
  }
  
}
