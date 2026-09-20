module Zenoo
  class Shader
    attr_reader :native

    def initialize(vert_source = nil, frag_source = nil)
      @native = Native::Shader.new(vert_source, frag_source)
    end

    def set_int(name, val)
      @native.set_int(name.to_s, val.to_i)
    end

    def set_float(name, val)
      @native.set_float(name.to_s, val.to_f)
    end

    def set_vec2(name, x, y)
      @native.set_vec2(name.to_s, x.to_f, y.to_f)
    end

    def set_vec3(name, x, y, z)
      @native.set_vec3(name.to_s, x.to_f, y.to_f, z.to_f)
    end

    def set_vec4(name, x, y, z, w)
      @native.set_vec4(name.to_s, x.to_f, y.to_f, z.to_f, w.to_f)
    end
  end
end
