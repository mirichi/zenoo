# frozen_string_literal: true

# ext/spinel/zenoo_ffi.rb の ffi_func 宣言を解析し、
# CRuby 拡張 C ソース ext/zenoo/zenoo_ext.c を自動生成するスクリプト。

FFI_PATH = File.expand_path("../ext/spinel/zenoo_ffi.rb", __dir__)
OUT_PATH = File.expand_path("../ext/zenoo/zenoo_ext.c", __dir__)

TYPE_MAP = {
  "void"   => { c_type: "void" },
  "int"    => { c_type: "int",        to_c: ->(v, i) { "int c_arg#{i} = NUM2INT(#{v});" },
                from_c: ->(r) { "INT2NUM(#{r})" } },
  "int64"  => { c_type: "int64_t",    to_c: ->(v, i) { "int64_t c_arg#{i} = (int64_t)NUM2LL(#{v});" },
                from_c: ->(r) { "LL2NUM(#{r})" } },
  "uint32" => { c_type: "uint32_t",   to_c: ->(v, i) { "uint32_t c_arg#{i} = (uint32_t)NUM2LL(#{v});" },
                from_c: ->(r) { "ULONG2NUM((unsigned long)(#{r}))" } },
  "float"  => { c_type: "float",      to_c: ->(v, i) { "float c_arg#{i} = (float)NUM2DBL(#{v});" },
                from_c: ->(r) { "DBL2NUM((double)(#{r}))" } },
  "double" => { c_type: "double",     to_c: ->(v, i) { "double c_arg#{i} = NUM2DBL(#{v});" },
                from_c: ->(r) { "DBL2NUM(#{r})" } },
  "ptr"    => { c_type: "void*",      to_c: ->(v, i) { "void* c_arg#{i} = NIL_P(#{v}) ? NULL : (void*)(uintptr_t)NUM2ULL(#{v});" },
                from_c: ->(r) { "(#{r}) ? ULL2NUM((unsigned long long)(uintptr_t)(#{r})) : Qnil" } },
  "str"    => { c_type: "const char*",
                to_c: ->(v, i) { "VALUE s_arg#{i} = #{v}; const char* c_arg#{i} = NIL_P(s_arg#{i}) ? NULL : StringValueCStr(s_arg#{i});" },
                from_c: ->(r) { "(#{r}) ? rb_utf8_str_new_cstr(#{r}) : Qnil" } },
  "binstr" => { c_type: "const void*",
                to_c: ->(v, i) {
                  "VALUE s_arg#{i} = #{v}; const void* c_arg#{i} = NULL;\n" \
                  "    if (!NIL_P(s_arg#{i})) { StringValue(s_arg#{i}); c_arg#{i} = (const void*)RSTRING_PTR(s_arg#{i}); }"
                } },
}.freeze

SPECIAL_FUNCS = %w[
  zen_set_frame_callback
  zen_ffi_clear_frame_callback
  zen_run_loop
  zen_update
  zen_set_gc_trigger_callback
].freeze

funcs = []
File.readlines(FFI_PATH, encoding: "UTF-8").each do |line|
  next unless line =~ /^\s*ffi_func\s+:([a-zA-Z0-9_]+),\s*\[(.*?)\],\s*:([a-zA-Z0-9_]+)/

  name = Regexp.last_match(1)
  raw_args = Regexp.last_match(2).strip
  ret = Regexp.last_match(3)
  args = raw_args.empty? ? [] : raw_args.scan(/:([a-zA-Z0-9_]+)/).flatten
  funcs << { name: name, args: args, ret: ret }
end

out = []
out << <<~'C'
  /*
   * AUTO-GENERATED FILE — DO NOT EDIT DIRECTLY.
   * Generated from ext/spinel/zenoo_ffi.rb by tools/generate_cruby_ext.rb
   */
  #include <ruby.h>
  #include <stdint.h>
  #include "../../include/zenoo.h"

  static VALUE s_frame_callback_proc = Qnil;
  static int s_pending_jump_tag = 0;

  static void rb_zenoo_gc_hook(void) {
      rb_gc();
  }

  static VALUE call_frame_callback_protected(VALUE arg) {
      return rb_funcall(arg, rb_intern("call"), 0);
  }

  static void rb_zenoo_frame_callback(void) {
      if (NIL_P(s_frame_callback_proc)) return;
      int state = 0;
      rb_protect(call_frame_callback_protected, s_frame_callback_proc, &state);
      if (state) {
          s_pending_jump_tag = state;
      }
  }

  /* ==========================================
   * Special CRuby Handlers (Callback / GC / Buffer)
   * ========================================== */
  static VALUE cruby_zen_set_frame_callback(VALUE self, VALUE cb) {
      (void)self;
      s_frame_callback_proc = cb;
      if (NIL_P(cb)) {
          zen_set_frame_callback(NULL);
      } else {
          zen_set_frame_callback(rb_zenoo_frame_callback);
      }
      return Qnil;
  }

  static VALUE cruby_zen_ffi_clear_frame_callback(VALUE self) {
      (void)self;
      s_frame_callback_proc = Qnil;
      zen_set_frame_callback(NULL);
      return Qnil;
  }

  static VALUE cruby_zen_run_loop(VALUE self, VALUE cb) {
      (void)self;
      s_frame_callback_proc = cb;
      s_pending_jump_tag = 0;
      zen_run_loop(NIL_P(cb) ? NULL : rb_zenoo_frame_callback);
      if (s_pending_jump_tag) {
          int tag = s_pending_jump_tag;
          s_pending_jump_tag = 0;
          rb_jump_tag(tag);
      }
      return Qnil;
  }

  static VALUE cruby_zen_update(VALUE self) {
      (void)self;
      s_pending_jump_tag = 0;
      int res = zen_update();
      if (s_pending_jump_tag) {
          int tag = s_pending_jump_tag;
          s_pending_jump_tag = 0;
          rb_jump_tag(tag);
      }
      return INT2NUM(res);
  }

  static VALUE cruby_zen_set_gc_trigger_callback(VALUE self, VALUE cb) {
      (void)self;
      (void)cb;
      zen_set_gc_trigger_callback(rb_zenoo_gc_hook);
      return Qnil;
  }

  static VALUE cruby_zen_ffi_image_get_pixels(VALUE self, VALUE v_ptr, VALUE v_byte_size) {
      (void)self;
      ZenImage* img = NIL_P(v_ptr) ? NULL : (ZenImage*)(uintptr_t)NUM2ULL(v_ptr);
      int byte_size = NUM2INT(v_byte_size);
      if (!img || byte_size <= 0) {
          return rb_str_new("", 0);
      }
      int w = zen_ffi_image_width(img);
      int h = zen_ffi_image_height(img);
      if (w <= 0 || h <= 0) {
          return rb_str_new("", 0);
      }
      long required = (long)w * (long)h * 4L;
      long alloc_size = ((long)byte_size > required) ? (long)byte_size : required;
      VALUE str = rb_str_new(NULL, alloc_size);
      zen_image_get_pixels(img, (uint32_t*)RSTRING_PTR(str));
      if (alloc_size > required) {
          rb_str_set_len(str, required);
      }
      return str;
  }

  /* ==========================================
   * Auto-generated FFI Wrappers
   * ========================================== */
C

funcs.each do |f|
  next if SPECIAL_FUNCS.include?(f[:name])

  params = ["VALUE self"] + f[:args].each_index.map { |i| "VALUE arg#{i}" }
  out << "static VALUE cruby_#{f[:name]}(#{params.join(', ')}) {"
  out << "    (void)self;"

  f[:args].each_with_index do |t, i|
    spec = TYPE_MAP.fetch(t) { raise "Unsupported arg FFI type :#{t} in #{f[:name]}" }
    raise "Arg type :#{t} missing converter in #{f[:name]}" unless spec[:to_c]

    out << "    #{spec[:to_c].call("arg#{i}", i)}"
  end

  call_args = f[:args].each_index.map { |i| "c_arg#{i}" }.join(", ")
  call_expr = "#{f[:name]}(#{call_args})"

  if f[:ret] == "void"
    out << "    #{call_expr};"
    out << "    return Qnil;"
  else
    spec = TYPE_MAP.fetch(f[:ret]) { raise "Unsupported return FFI type :#{f[:ret]} in #{f[:name]}" }
    raise "Return type :#{f[:ret]} missing converter in #{f[:name]}" unless spec[:from_c]

    ret_decl = f[:ret] == "ptr" ? "void* ret = (void*)(#{call_expr});" : "#{spec[:c_type]} ret = #{call_expr};"
    out << "    #{ret_decl}"
    out << "    return #{spec[:from_c].call('ret')};"
  end

  out << "}"
  out << ""
end

out << <<~'C'
  void Init_zenoo(void) {
      rb_gc_register_address(&s_frame_callback_proc);
      zen_set_gc_trigger_callback(rb_zenoo_gc_hook);

      VALUE rb_mZenoo = rb_define_module("Zenoo");
      VALUE rb_mNative = rb_define_module_under(rb_mZenoo, "Native");
      VALUE rb_mC = rb_define_module_under(rb_mNative, "C");

C

funcs.each do |f|
  out << "    rb_define_singleton_method(rb_mC, \"#{f[:name]}\", cruby_#{f[:name]}, #{f[:args].length});"
end
out << "    rb_define_singleton_method(rb_mC, \"zen_ffi_image_get_pixels\", cruby_zen_ffi_image_get_pixels, 2);"
out << "}"

File.write(OUT_PATH, out.join("\n") + "\n", mode: "wb:UTF-8")
puts "Generated #{OUT_PATH} (#{funcs.length + 1} singleton methods on Zenoo::Native::C)"
