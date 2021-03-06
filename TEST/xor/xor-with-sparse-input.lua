learning_rate  = 0.4
momentum       = 0.1
weight_decay   = 1e-05
semilla        = 1234
aleat          = random(semilla)
num_weights    = 9
bunch_size     = tonumber(arg[1]) or 64
m = matrix.fromString[[
    9
    ascii
      -0.5 -1.2 1.0
      -2.0 4.0 -4.0
      -1.0 2.0 2.0
]]

function show_weights(trainer, filter)
  if not filter then filter = function(x) return x end end
  print()
  for i = 1,ds_input:numPatterns() do
    local out = trainer:calculate(ds_input:getPattern(i)):toTable()
    value = filter(out[1])
    --printf("%s\t %s\n",
    --table.concat(ds_input:getPattern(i),","),
    --value)
    print(value)
  end
  print()
  for _,wname in ipairs({ "b1", "w1", "b2", "w2" }) do
    local w = trainer.weights_table[wname]:copy_to():toTable()
    print(wname, table.concat(w, " "))
  end
end

function load_initial_weights(weights_table)
  weights_table["b1"]:load{ w=m, first_pos=0, column_size=3 }
  weights_table["w1"]:load{ w=m, first_pos=1, column_size=3 }
  weights_table["b2"]:load{ w=m, first_pos=6, column_size=3 }
  weights_table["w2"]:load{ w=m, first_pos=7, column_size=3 }
end

-----------------------------------------------------------

net_component=ann.mlp.all_all.generate("2 inputs 2 logistic 1 logistic")
trainer=trainable.supervised_trainer(net_component)
trainer:set_option("learning_rate", learning_rate)
trainer:set_option("momentum",      momentum)
trainer:set_option("weight_decay",  weight_decay)
trainer:build()
trainer:set_loss_function(ann.loss.mse(net_component:get_output_size()))
load_initial_weights(trainer.weights_table)

m_xor = matrix.fromString[[
    4 3
    ascii
    0 0 0
    0 1 1
    1 0 1
    1 1 0
]]

ds_input  = dataset.token.vector(2)
ds_output = dataset.token.vector(1)

t = tokens.vector.sparse()
ds_input:push_back(t)

t = tokens.vector.sparse()
t:push_back(0, 1.0)
ds_input:push_back(t)

t = tokens.vector.sparse()
t:push_back(1, 1.0)
ds_input:push_back(t)

t = tokens.vector.sparse()
t:push_back(0, 1.0)
t:push_back(1, 1.0)
ds_input:push_back(t)

------------------------------

t = tokens.matrix( matrix.col_major(1,1,{0.0}) )
ds_output:push_back(t)

t = tokens.matrix( matrix.col_major(1,1,{1.0}) )
ds_output:push_back(t)

t = tokens.matrix( matrix.col_major(1,1,{1.0}) )
ds_output:push_back(t)

t = tokens.matrix( matrix.col_major(1,1,{0.0}) )
ds_output:push_back(t)

-----------------------
-- Valores iniciales --
-----------------------

load_initial_weights(trainer.weights_table)

data={
  input_dataset  = ds_input,
  output_dataset = ds_output,
  shuffle        = aleat,
  bunch_size     = bunch_size
}
print ("\nAfter one epoch")
trainer:train_dataset(data)
show_weights(trainer)

print ("\nAfter two epochs")
trainer:train_dataset(data)
show_weights(trainer)

net_component:pop()
net_component:push( ann.components.actf.log_logistic() )
trainer=trainable.supervised_trainer(net_component)
trainer:build()
trainer:set_loss_function(ann.loss.cross_entropy(net_component:get_output_size()))
load_initial_weights(trainer.weights_table)

print ("\nAfter 30000 epochs")
for i=3,30000 do
  print(i, trainer:train_dataset(data))
end
show_weights(trainer, math.exp)
