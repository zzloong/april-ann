imageSVG = imageSVG or {}
imageSVG.__index = imageSVG
setmetatable(imageSVG, imageSVG)

imageSVG.__tostring = function() return "imageSVG" end

function imageSVG:__call(params)

    local obj = {}
    
    obj.width = params.width or -1
    obj.height = params.height or -1

    print(obj.width, obj.height)
    -- Header, body and footer are tables of strings
    obj.header = {}
    obj.body   = {}
    obj.footer = {}
    
    setmetatable(obj, self)
    return obj

end

function imageSVG:setHeader()

  self.header = {}
  table.insert(self.header, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
	table.insert(self.header, "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 20001102//EN\" \"http://www.w3.org/TR/2000/CR-SVG-20001102/DTD/svg-20001102.dtd\">\n")

--  local swidth  = tostring(self.width) or "100%"
--  local sheight = tostring(self.height) or "100%"
  
  local swidth  = (self.width ~= -1 and tostring(self.width)) or "100%"
  local sheight = (self.height ~= -1 and tostring(self.height)) or "100%"
  
	table.insert(self.header,string.format("<svg width=\"%s\" height=\"%s\">\n", swidth, sheight))

  table.insert(self.header, "<g transform=\"translate(0,0)\">\n")
end

function imageSVG:setFooter()
  self.footer = {}
  table.insert(self.footer, "</g>\n</svg>")
end

-- Recieves a table with points x,y
function imageSVG:addPathFromTable(path, params)
    --params treatment

    local id = params.id or ""
    local stroke = params.stroke or "black"
    local stroke_width = params.stroke_width or "1"

    local buffer = {}

    table.insert(buffer, string.format("<path id = \"%s\" d = \"", id))

    for i, v in ipairs(path) do
        if (i == 1) then
            table.insert(buffer, string.format("M %d %d ", v[1], v[2]))
        else
            table.insert(buffer, string.format("L %d %d ", v[1], v[2]))
        end

    end
    table.insert(buffer, string.format("\"fill=\"none\" stroke = \"%s\" stroke-width = \"%s\"/>", stroke, stroke_width))

    table.insert(self.body, table.concat(buffer))

end

function imageSVG:getHeader()
    return table.concat(self.header) 
end
function imageSVG:getBody()
    return table.concat(self.body) 
end
function imageSVG:getFooter()
    return table.concat(self.footer) 
end
function imageSVG:getString()
    return table.concat({self:getHeader(), self:getBody(), self:getFooter()})
end
function imageSVG:write(filename)
    print("\nStarting to write Svg-file.")
    file = io.open(filename, "w")
    file:write(self:getHeader())
    file:write(self:getBody())
    file:write(self:getFooter())
end

-- Each element of the table is a path
function imageSVG:addPaths(paths)

    local colors = { "red", "blue", "green", "green", "orange"}

    for i, path in ipairs(paths) do
        local color = "black"
        if (i <= #colors) then
            color = colors[i]
        end
        self:addPathFromTable(path,{stroke = color})
    end
end

function imageSVG:resize(height, width)
    self.height = height
    self.width = width
end

-- Extra image function
function imageSVG.overlapSVG(png_file, svg_file)
  os.execute('inkscape -z -e '..png_file..' '..svg_file..' 1>/dev/null 2>/dev/null')
end

