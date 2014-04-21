local trainable_qlearning_trainer_methods,
trainable_qlearning_trainer_class_metatable=class("trainable.qlearning_trainer")

-----------------------------
-- QLEARNING TRAINER CLASS --
-----------------------------

function trainable_qlearning_trainer_class_metatable:__call(t)
  local params = get_table_fields(
    {
      sup_trainer = { isa_match=trainable.supervised_trainer, mandatory=true },
      discount = { type_match="number", mandatory=true, default=0.6 },
      lambda = { type_match="number", mandatory=true, default=0.6 },
      gradients = { mandatory=false, default=matrix.dict() },
      traces = { mandatory=false, default=matrix.dict() },
      noise = { mandatory=false, default=ann.components.base() },
      clampQ = { mandatory=false },
    }, t)
  local tr = params.sup_trainer
  local thenet  = tr:get_component()
  local weights = tr:get_weights_table()
  local optimizer = tr:get_optimizer()
  local obj = {
    tr = tr,
    thenet = thenet,
    weights = weights,
    optimizer = optimizer,
    gradients = params.gradients,
    traces = params.traces,
    discount = params.discount,
    lambda = params.lambda,
    noise = params.noise,
    nactions = thenet:get_output_size(),
    clampQ = params.clampQ,
  }
  return class_instance(obj, self)
end

-- PRIVATE METHOD
-- updates the weights given the previous state, the action, the current state
-- and the observed reward
local function trainable_qlearning_trainer_train(self, prev_state, prev_action, state, reward)
  local noise = self.noise
  local weights = self.weights
  local thenet = self.thenet
  local optimizer = self.optimizer
  local gradients = self.gradients
  local traces = self.traces
  local nactions = self.nactions
  local discount = self.discount
  local lambda = self.lambda
  local clampQ = self.clampQ
  -- add random noise if given
  noise:reset(1)
  local prev_state = noise:forward(prev_state, true)
  noise:reset(0)
  local state = noise:forward(state, true)
  local error_grad = matrix.col_major(1, nactions):zeros()
  local loss,Qsp,Qs
  loss,gradients,Qsp,Qs,expected_Qsa =
    optimizer:execute(function(it)
                        assert(not it or it == 0)
                        thenet:reset(it)
                        local Qsp = thenet:forward(state):get_matrix()
                        local Qs  = thenet:forward(prev_state,true):get_matrix()
                        local Qsa = Qs:get(1, prev_action)
                        local delta = reward + discount * Qsp:max() - Qsa
                        local diff = delta
                        local loss = 0.5 * diff * diff
                        error_grad:set(1, prev_action, -diff)
                        thenet:backprop(error_grad)
                        gradients:zeros()
                        gradients = thenet:compute_gradients(gradients)
                        if traces:size() == 0 then
                          for name,g in pairs(gradients) do
                            traces[name] = matrix.as(g):zeros()
                          end
                        end
                        traces:scal(lambda*discount)
                        traces:axpy(1.0, gradients)
                        return loss,traces,Qsp,Qs,expected_Qsa
                      end,
                      weights)
  self.gradients = gradients
  return loss,Qsp,Qs,expected_Qsa
end

-- takes the previos action, the current state (ANN input) and the reward,
-- updates the ANN weights and returns the current output Q(state,a)
function trainable_qlearning_trainer_methods:one_step(action, state, reward)
  local Qsp
  if self.prev_state then
    local loss,Qs,expected_Qsa
    loss,Qsp,Qs,expected_Qsa = trainable_qlearning_trainer_train(self,
                                                                 self.prev_state,
                                                                 action,
                                                                 state,
                                                                 reward)
    self.Qprob = (self.Qprob or 0) + math.log(Qs:get(1,action))
    -- printf("%8.2f Q(s): %8.2f %8.2f %8.2f  E(Q(s)): %8.2f   ACTION: %d  REWARD: %6.2f  LOSS: %8.4f  MP: %.4f %.4f\n",
    --        -self.Qprob,
    --        Qs:get(1,1), Qs:get(1,2), Qs:get(1,3),
    --        expected_Qsa,
    --        action, reward, loss,
    --        self.tr:norm2("w."), self.tr:norm2("b."))
  else
    self.noise:reset(0)
    local state = self.noise:forward(state,true)
    Qsp = self.thenet:forward(state):get_matrix()
  end
  self.prev_state = state
  return Qsp
end

-- returns an object where you can add several (state, action, next_state,
-- reward) batches, and at the end, build a pair of input/output datasets for
-- supervised training
function trainable_qlearning_trainer_methods:get_batch_builder()
  return trainable.qlearning_trainer.batch_builder(self)
end

-- begins a new sequence of training
function trainable_qlearning_trainer_methods:reset()
  self.prev_state = nil
  self.traces:zeros()
  self.Qprob = 0
end

function trainable_qlearning_trainer_methods:calculate(...)
  return self.tr:calculate(...)
end

function trainable_qlearning_trainer_methods:randomize_weights(...)
  return self.tr:randomize_weights(...)
end

function trainable_qlearning_trainer_methods:set_option(...)
  return self.tr:set_option(...)
end

function trainable_qlearning_trainer_methods:set_layerwise_option(...)
  return self.tr:set_layerwise_option(...)
end

function trainable_qlearning_trainer_methods:get_option(...)
  return self.tr:get_option(...)
end

function trainable_qlearning_trainer_methods:has_option(...)
  return self.tr:has_option(...)
end

function trainable.qlearning_trainer.load(filename)
  return util.deserialize(filename)
end

function trainable_qlearning_trainer_methods:save(filename,format)
  util.serialize(self, filename, format)
end

function trainable_qlearning_trainer_methods:to_lua_string(format)
  return string.format("trainable.qlearning_trainer{%s}",
                       table.tostring({
                                        sup_trainer = self.tr,
                                        noise = self.noise,
                                        discount = self.discount,
                                        lambda = self.lambda,
                                        traces = self.traces,
                                        gradients = self.gradients,
                                        clampQ = self.clampQ,
                                      },
                                      format))
end

------------------------------------------------------------------------------

local trainable_batch_builder_methods,
trainable_batch_builder_class_metatable=class("trainable.qlearning_trainer.batch_builder")

function trainable_batch_builder_class_metatable:__call(qlearner)
  local obj = { qlearner = qlearner, batch={} }
  return class_instance(obj,self)
end

function trainable_batch_builder_methods:add(prev_state, output, action, reward)
  assert(isa(prev_state, matrix),   "Needs a matrix as 1st argument")
  assert(isa(prev_state, matrix),   "Needs a matrix as 2nd argument")
  assert(type(action) == "number",  "Needs a number as 3rd argument")
  assert(type(reward) == "number",  "Needs a matrix as 4th argument")
  table.insert(self.batch,
               {
                 prev_state:clone("row_major"):rewrap(prev_state:size()),
                 action,
                 reward,
                 output:clone("row_major"):rewrap(output:size()),
               })
  if self.state_size then
    assert(self.state_size == prev_state:size(), "Found different state sizes")
  end
  self.state_size = prev_state:size()
end

function trainable_batch_builder_methods:compute_dataset_pair()
  assert(self.state_size, "Several number of adds is needed")
  local discount = self.qlearner.discount
  local inputs  = matrix(#self.batch, self.state_size)
  local outputs = matrix(#self.batch, self.qlearner.nactions):zeros()
  local mask = outputs:clone()
  local mask_row
  local Qs
  local state
  local acc_reward = 0
  for i=#self.batch,1,-1 do
    local prev_state,action,reward,output = table.unpack(self.batch[i])
    --
    acc_reward = reward + discount * acc_reward
    Qs = outputs:select(1,i,Qs):set(action,acc_reward)
    mask_row = mask:select(1,i,mask_row):set(action,1)
    --
    state = inputs:select(1,i):copy(prev_state)
  end
  if self.qlearner.clampQ then outputs:map(self.qlearner.clampQ) end
  return dataset.matrix(inputs),dataset.matrix(outputs),dataset.matrix(mask)
end

-------------------------------------------------------------------------------

trainable.qlearning_trainer.strategies = {}

trainable.qlearning_trainer.strategies.make_epsilon_greedy = function(actions,
                                                                      epsilon,
                                                                      rnd)
  assert(type(actions) == "table", "Needs an actions table as 1st argument")
  local epsilon = epsilon or 0.1
  local rnd = rnd or random()
  return function(output)
    local coin = rnd:rand()
    local max,action = output:max()
    local min = output:min()
    local diff = max - min
    local rel_diff = diff / (max + min)
    if coin < epsilon or rel_diff < 0.01 then
      action = rnd:choose(actions)
    end
    return action
  end
end

trainable.qlearning_trainer.strategies.make_epsilon_decresing = function(actions,
                                                                         epsilon,
                                                                         decay,
                                                                         rnd)
  assert(type(actions) == "table", "Needs an actions table as 1st argument")
  local epsilon = epsilon or 0.1
  local decay = decay or 0.9
  local rnd = rnd or random()
  return function(output)
    local coin = rnd:rand()
    local max,action = output:max()
    local min = output:min()
    local diff = max - min
    local rel_diff = diff / (max + min)
    if coin < epsilon or rel_diff < 0.01 then
      action = rnd:choose(actions)
    end
    epsilon = epsilon * decay
    return action
  end
end

trainable.qlearning_trainer.strategies.make_softmax = function(actions,rnd)
  assert(type(actions) == "table", "Needs an actions table as 1st argument")
  local rnd = rnd or random()
  return function(output)
    assert(math.abs(1-output:sum()) < 1e-03,
           "Softmax strategy needs normalized outputs")
    local dice = random.dice(output:toTable())
    local action = dice:thrown(rnd)
    return action
  end
end
