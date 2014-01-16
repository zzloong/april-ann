-- OVERWRITTING TOSTRING FUNCTION
class_extension(matrixDouble, "to_lua_string",
                function(self, format)
                  return string.format("matrixDouble.fromString[[%s]]",
                                       self:toString(format or "string"))
                end)

matrixDouble.meta_instance.__tostring =
  matrix.__make_generic_print__("MatrixDouble",
				function(value)
				  return string.format("% -11.6g", value)
				end)

function matrixDouble.loadfile()
  error("Deprecated, use fromFilename method")
end

function matrixDouble.savefile()
  error("Deprecated, use toFilename method")
end
