-- This file implements specific operations related with ANNs. Only the most
-- numerically inestable are implemented.

local AD = autodiff
AD.ann   = AD.ann or {}

-- RECTIFIED LINER
function AD.ann.relu(a)
  return AD.op.cmul(a, AD.op.gt(a,0))
end

-- LOGISTIC ACTIVATION FUNCTION
function AD.ann.logistic(a)
  local a = AD.coercion(a)
  local s = AD.gen_op('logistic', AD.dtypes.MATRIX, {a},
		      function(self, ...)
			local a = self.args[1]:eval(...)
			return a:clone():scal(-1):exp():scalar_add(1.0):div(1.0)
		      end,
		      function(self, seed, result)
			local a     = self.args[1]
			local dself = AD.op.cmul(self, (1-self))
			a:diff(AD.op.cmul(seed, dself), result)
			return result
		      end,
		      function(self, dest)
			local a = self.args[1]
			local tbl = { a.var_name, ":clone()", ":scal(-1)",
				      ":exp()", ":scalar_add(1.0)",
				      ":div(1.0)" }
			dest:write_expr_assign(self.var_name,
					       table.concat(tbl, ""))
		      end)
  return s  
end

-- LOG SOFTMAX ACTIVATION FUNCTION WITH CROSS-ENTROPY LOSS
function AD.ann.cross_entropy_log_softmax(input, target, dim)
  assert(type(dim)=="number", "The 3rd argument (dim) must be a number")
  local other_dim = 3 - dim
  local i   = AD.coercion(input)
  local t   = AD.coercion(target)
  local output = AD.ann.log_softmax(i,dim)
  -- ignore the gradient of softmax, it is computed at the loss function
  output:ignore_gradient()
  -- cross_entropy
  s = AD.gen_op('CE', AD.dtypes.MATRIX, {output,t},
		function(self, ...)
		  local i   = self.args[1]:eval(...)
		  local t   = self.args[2]:eval(...)
		  return -i:clone():cmul(t):sum(other_dim)
		end,
		function(self, seed, result)
		  local i = self.args[1]
		  local t = self.args[2]
		  local dself = AD.op.exp(i) - t
		  if dim == 1 then seed:set_broadcast(true, false)
		  else             seed:set_broadcast(false, true) end
		  local seed  = AD.op.fill(i, seed)
		  i:diff(AD.op.cmul(seed, dself), result)
		  return result
		end,
		function(self, dest)
		  local i   = self.args[1]
		  local t   = self.args[2]
		  dest:write_expr_assign(self.var_name,
					 string.format("-%s:clone():cmul(%s):sum(%d)",
						       i.var_name,
						       t.var_name,
						       other_dim))
		end)
  return s
end

-- LOG-SOFTMAX
function AD.ann.log_softmax(a,dim)
  assert(type(dim)=="number", "The 2nd argument (dim) must be a number")
  local other_dim = 3 - dim
  local a = AD.coercion(a)
  local s = AD.gen_op('log_softmax', AD.dtypes.MATRIX, {a},
		      function(self, ...)
			local i   = self.args[1]:eval(...)
			local max = i:max(other_dim)
			local out = i:clone()
			local slice
			for k=1,out:dim(dim) do
			  slice = out:select(dim,k,slice)
			  slice:scalar_add(-max:get(
					     (dim==1 and k) or 1,
					     (dim==2 and k) or 1))
			end
			out:exp()
			for k=1,out:dim(dim) do
			  slice = out:select(dim,k,slice)
			  local sum = slice:sum()
			  slice:scalar_add(-math.log(sum))
			end
			return out
		      end,
		      function(self, seed, result)
			local a = self.args[1]
			local dself = AD.op.cmul(AD.op.exp(self), (1-AD.op.exp(self)))
			a:diff(AD.op.cmul(seed, dself), result)
			return result
		      end,
		      function(self, dest)
			local i   = self.args[1]
			local max = AD.gen_var_name()
			local sum = AD.gen_var_name()
			dest:write_expr_assign(self.var_name,
					       string.format("%s:clone()",
							     i.var_name))
			local max = AD.gen_var_name()
			dest:write_expr_assign(max,
					       string.format("%s:max(%d)",
							     self.var_name,
							     other_dim))
			local slice = AD.gen_var_name()
			dest:write_var(slice)
			if dim == 1 then
			  dest:write_expr_block(string.format([[
for k=1,%s:dim(%d) do
  %s = %s:select(%d,k,%s)
  %s:scalar_add(-%s:get(k,1))
end
]],
							      self.var_name, dim,
							      slice, self.var_name, dim, slice,
							      slice, max))
			else -- if dim == 1 ... else
			  dest:write_expr_block(string.format([[
for k=1,%s:dim(%d) do
  %s = %s:select(%d,k,%s)
  %s:scalar_add(-%s:get(1,k))
end
]],
							      
							      self.var_name, dim,
							      slice, self.var_name, dim, slice,
							      slice, max))
			end
			local sum_exp = AD.gen_var_name()
			dest:write_expr_assign(sum_exp,
					       string.format("%s:clone():exp()",
							     self.var_name))
			dest:write_expr_assign(sum_exp,
					       string.format("%s:sum(%d)",
							     sum_exp,
							     other_dim))
			if dim == 1 then
			  dest:write_expr_block(string.format([[
for k=1,%s:dim(%d) do
  %s = %s:select(%d,k,%s)
  %s:scalar_add( -math.log(%s:get(k,1)) )
end
]],
							      self.var_name, dim,
							      slice, self.var_name, dim, slice,
							      slice, sum_exp))
			else -- if dim == 1 then ... else
			  dest:write_expr_block(string.format([[
for k=1,%s:dim(%d) do
  %s = %s:select(%d,k,%s)
  %s:scalar_add( -math.log(%s:get(1,k)) )
end
]],
							      
							      self.var_name, dim,
							      slice, self.var_name, dim, slice,
							      slice, sum_exp))
			end
		      end)
  return s
end
