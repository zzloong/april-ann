local tied_model_manager,tied_model_manager_methods =
  class("tied_model_manager")
_G.tied_model_manager = tied_model_manager -- global environment

----------------------------
-- Constructor
----------------------------
function tied_model_manager:constructor(tiedlist_file)
  self.tiedlist = {}
  self.name2id  = {}
  self.id2name  = {}
  local id = 1
  for line in tiedlist_file:lines() do
    local tokens = string.tokenize(line)
    if tokens[2] then
      self.name2id[tokens[1]] = self.name2id[tokens[2]]
    else
      self.name2id[tokens[1]] = id
      self.id2name[id]        = tokens[1]
      id = id + 1
    end
    self.tiedlist[tokens[1]] = tokens[2] or tokens[1]
  end
end

function tied_model_manager_methods:get_model(phone)
  return self.tiedlist[phone]
end

-- Searchs a triphone. search_triphone("a","b","c") looks for
-- "a-b+c", falling back to diphones and monophones if it's not
-- found
function tied_model_manager_methods:search_triphone(left, phone, right)
  local selected
  if left and right then
    -- both contexts
    -- If triphone matches, OK. Else down to diphones and so on.
    if self.tiedlist[left.."-"..phone.."+"..right] then
      selected=left.."-"..phone.."+"..right
    elseif self.tiedlist[left.."-"..phone] then
      selected=left.."-"..phone
    elseif self.tiedlist[phone.."+"..right] then
      selected=phone.."+"..right
    elseif self.tiedlist[phone] then
      selected=phone
    else
      error("can't find triphone for "..left.."-"..phone.."+"..right)
    end
  elseif (not left) and right then
    -- Right context only
    if self.tiedlist[phone.."+"..right] then
      selected=phone.."+"..right
    elseif self.tiedlist[phone.."+sil"] then
      selected=phone.."+sil"
    elseif self.tiedlist[phone] then
      selected=phone
    else
      error("can't find triphone for (nil)-"..phone.."+"..right)
    end
  elseif left and (not right) then
    -- Left context only
    if self.tiedlist[left.."-"..phone] then
      selected=left.."-"..phone
    elseif self.tiedlist["sil-"..phone] then
      selected="sil-"..phone
    elseif self.tiedlist[phone] then
      selected=phone
    else
      error("can't find triphone for "..left.."-"..phone.."+(nil)")
    end
  else
    -- Monophone
    if self.tiedlist[phone] then
      selected=phone
    else
      error("can't find triphone for (nil)-"..phone.."+(nil)")
    end
  end
  
  return self.tiedlist[selected]
end

function tied_model_manager_methods:search_triphone_sequence(sequence)
  local result = {}
  for i=1,#sequence do
    local left = nil
    local right = nil
    if i>1 then left = sequence[i-1] end
    if i<#sequence then right = sequence[i+1] end
    table.insert(result, self:search_triphone(left, sequence[i], right))
  end
  return result
end



