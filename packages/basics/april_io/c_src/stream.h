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
#ifndef STREAM_H
#define STREAM_H

#include <cstdio>
#include <cstring>

#include "constString.h"
#include "error_print.h"
#include "referenced.h"
#include "stream.h"
#include "unused_variable.h"

namespace april_io {
  /**
   * The Stream is the parent class which needs to be dervied by I/O
   * facilities.
   */
  class Stream : public Referenced {
  public:
    Stream();
    virtual ~Stream();
    
    /// Returns if the stream is properly opened and not EOF and no errors.
    virtual bool good() const;

    /// Reads a string delimited by any of the given chars and puts it into the
    /// given Stream. If delim==0 then this method ends when dest->eof() is
    /// true.
    virtual size_t get(Stream *dest, const char *delim);
    
    /// Reads a string with max_size length and delimited by any of the given
    /// chars and puts it into the given Stream.
    virtual size_t get(Stream *dest, size_t max_size, const char *delim);
    
    /// Reads a string of a maximum given size delimited by any of the given
    /// chars and puts it into the given char buffer.
    virtual size_t get(char *dest, size_t size, const char *delim);
    
    /// Puts a string of a maximum given size taken from the given Stream.
    virtual size_t put(Stream *source, size_t size);
    
    /// Puts a string of a maximum given size taken from the given char buffer.
    virtual size_t put(const char *source, size_t size);
    
    /// Writes a set of values following the given format. Equals to C printf.    
    virtual int printf(const char *format, ...);
    
    ///////// ABSTRACT INTERFACE /////////
    
    virtual bool eof() const = 0;
    
    virtual bool isOpened() const = 0;

    virtual void close() = 0;
    
    /// Moves the stream cursor to the given offset from given whence position.
    virtual off_t seek(int whence, int offset);
    
    /// Forces to write pending data at stream object.
    virtual void flush() = 0;
    
    /// Modifies the behavior of the buffer.
    virtual int setvbuf(int mode, size_t size) = 0;
    
    /// Indicates if an error has been produced.
    virtual bool hasError() const = 0;
    
    /// Returns an internal string with the last error message.
    virtual const char *getErrorMsg() const = 0;
    
  protected:
    
    // Auxiliary proteced methods
    virtual size_t getInBufferAvailableSize() const = 0;
    virtual const char *getInBuffer(size_t &buffer_len, size_t max_size,
                                    const char *delim) = 0;
    virtual char *getOutBuffer(size_t &buffer_len, size_t max_size) = 0;
    virtual void moveInBuffer(size_t len) = 0;
    virtual void moveOutBuffer(size_t len) = 0;
    
  private:
    void trimInBuffer(const char *delim);
  };
  
} // namespace april_io

#endif // STREAM_H
