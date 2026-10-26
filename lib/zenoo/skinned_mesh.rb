# frozen_string_literal: true

module Zenoo
  # ====================================================================
  # 2D ボーン（関節ノード）クラス
  # Sprite を継承し、画像を持たない関節階層ノードとして機能します。
  # デフォルトでは width = 0, height = 0, anchor = :top_left, pivot = :top_left となり、
  # (x, y) がそのまま親ボーンからの相対オフセットおよび自身の回転中心（関節点）になります。
  # ====================================================================
  class Bone < Sprite
    attr_accessor :name, :length

    def initialize(x = 0.0, y = 0.0, angle: 0.0, length: 0.0, name: nil, parent: nil,
                   scale_x: 1.0, scale_y: 1.0, width: nil, height: nil,
                   anchor: :top_left, pivot: :top_left)
      super(x, y, nil, width: width, height: height, anchor: anchor, pivot: pivot, parent: parent)
      @name = name
      @length = length.to_f
      self.angle = angle if angle != 0.0
      self.scale_x = scale_x if scale_x != 1.0
      self.scale_y = scale_y if scale_y != 1.0
    end

    # ボーン先端のワールド座標 (length が設定されている場合、または子ボーンがある場合)
    def tip_world_pos
      wx = world_pivot_x
      wy = world_pivot_y
      if @length > 0.0001
        len = @length * world_scale_x
        [wx + len * world_cos, wy + len * world_sin]
      elsif @children && !@children.empty?
        ch = @children[0]
        [ch.world_pivot_x, ch.world_pivot_y]
      else
        [wx, wy]
      end
    end

    # ボーンおよび子ボーン階層のデバッグ可視化描画
    def draw_debug(color: :cyan, joint_color: :yellow, width: 3.0, joint_radius: 5.0, recursive: true, camera: true, z: 1000.0)
      wx = world_pivot_x
      wy = world_pivot_y

      if @children && !@children.empty?
        if @length > 0.0001
          tx, ty = tip_world_pos
          Window.draw_line(wx, wy, tx, ty, color: color, width: width, cap: :round, camera: camera, z: z)
          Window.draw_circle(tx, ty, joint_radius * 0.7, color: color, camera: camera, z: z + 0.01)
        end
        @children.each do |ch|
          next unless ch.is_a?(Sprite)
          cwx = ch.world_pivot_x
          cwy = ch.world_pivot_y
          if @length <= 0.0001
            Window.draw_line(wx, wy, cwx, cwy, color: color, width: width, cap: :round, camera: camera, z: z)
          else
            Window.draw_line(wx, wy, cwx, cwy, color: [180, 180, 220, 120], width: width * 0.6, cap: :round, camera: camera, z: z - 0.01)
          end
          if recursive && ch.respond_to?(:draw_debug)
            ch.draw_debug(color: color, joint_color: joint_color, width: width, joint_radius: joint_radius, recursive: true, camera: camera, z: z)
          end
        end
      elsif @length > 0.0001
        tx, ty = tip_world_pos
        Window.draw_line(wx, wy, tx, ty, color: color, width: width, cap: :round, camera: camera, z: z)
        Window.draw_circle(tx, ty, joint_radius * 0.7, color: color, camera: camera, z: z + 0.01)
      end

      Window.draw_circle(wx, wy, joint_radius, color: joint_color, border_color: :black, border_width: 1.5, camera: camera, z: z + 0.02)
    end

    def self.draw_debug(bones, **kwargs)
      if bones.is_a?(Array)
        bones.each do |b|
          b.draw_debug(**kwargs, recursive: false) if b.respond_to?(:draw_debug)
        end
      elsif bones.respond_to?(:draw_debug)
        bones.draw_debug(**kwargs)
      end
    end
  end

  # ====================================================================
  # 2D スキニングメッシュ (SkinnedMesh)
  # 画像を格子状メッシュに自動分割し、ボーン (Bone / Sprite) 階層と
  # ウェイトマップ (Image) を用いて頂点シェーダーで高速にスキニング変形します。
  # ====================================================================
  class SkinnedMesh
    MAX_BONES = 8

    SKINNED_VERTEX_SHADER = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec2 in_pos;
      layout (location = 1) in vec2 in_uv;
      layout (location = 2) in vec4 in_color;

      uniform vec2 u_resolution;
      uniform float u_flip_y;
      uniform sampler2D u_weight_map;
      uniform vec4 u_weight_uv_rect;     // u0, v0, uw, vh (SubImage 対応)
      uniform int u_weight_mode;         // 0: 1ボーン, 1: 2ボーン輝度グラデーション, 2: RGBA 4チャンネル, 3: 8ボーン(自動折り返し等)
      uniform int u_bone_count;
      uniform vec4 u_bone_m[8];          // 各ボーンの回転・拡大縮小 2x2 行列 (m00, m01, m10, m11)
      uniform vec4 u_bone_t[8];          // 各ボーンの平行移動ベクトル (tx, ty, 0, 0)
      uniform vec4 u_view;               // tx, ty, zoom, 0 (カメラ・画面オフセット)
      uniform vec4 u_tint;               // 全体乗算カラー (r, g, b, a)

      out vec4 v_color;
      out vec2 v_uv;

      vec2 transform_bone(int idx, vec2 p) {
          vec4 m = u_bone_m[idx];
          vec2 t = u_bone_t[idx].xy;
          return vec2(m.x * p.x + m.y * p.y + t.x,
                      m.z * p.x + m.w * p.y + t.y);
      }

      void main() {
          vec2 norm_uv = in_color.xy;
          vec2 w_uv = u_weight_uv_rect.xy + norm_uv * u_weight_uv_rect.zw;
          vec4 w_tex = texture(u_weight_map, w_uv);

          vec2 skinned_pos = in_pos;

          if (u_bone_count <= 0) {
              skinned_pos = in_pos;
          } else if (u_bone_count == 1 || u_weight_mode == 0) {
              skinned_pos = transform_bone(0, in_pos);
          } else if (u_weight_mode == 1) {
              // 2ボーン 白黒(輝度/R)グラデーションモード: 黒(0.0)=Bone0, 白(1.0)=Bone1
              float t = clamp(w_tex.r, 0.0, 1.0);
              vec2 p0 = transform_bone(0, in_pos);
              vec2 p1 = transform_bone(1, in_pos);
              skinned_pos = mix(p0, p1, t);
          } else if (u_weight_mode == 3) {
              // 連続チェーンモード (ボーン数 2..8): Rチャンネルに正規化されたチェーン位置 (0.0 .. 1.0) が格納されている
              float pos_f = clamp(w_tex.r, 0.0, 1.0) * float(u_bone_count - 1);
              int idx0 = int(floor(pos_f));
              int idx1 = min(idx0 + 1, u_bone_count - 1);
              float frac_t = pos_f - float(idx0);
              // smoothstep 補間で関節の折れを滑らかにする
              float smooth_t = frac_t * frac_t * (3.0 - 2.0 * frac_t);
              vec2 p0 = transform_bone(idx0, in_pos);
              vec2 p1 = transform_bone(idx1, in_pos);
              skinned_pos = mix(p0, p1, smooth_t);
          } else {
              // RGBA 4チャンネル独立ウェイトモード (R=Bone0, G=Bone1, B=Bone2, A=Bone3)
              float w0 = w_tex.r;
              float w1 = (u_bone_count > 1) ? w_tex.g : 0.0;
              float w2 = (u_bone_count > 2) ? w_tex.b : 0.0;
              float w3 = (u_bone_count > 3) ? w_tex.a : 0.0;
              float sum = w0 + w1 + w2 + w3;
              if (sum > 0.0001) {
                  float inv_sum = 1.0 / sum;
                  w0 *= inv_sum;
                  w1 *= inv_sum;
                  w2 *= inv_sum;
                  w3 *= inv_sum;
                  skinned_pos = transform_bone(0, in_pos) * w0;
                  if (u_bone_count > 1 && w1 > 0.0) skinned_pos += transform_bone(1, in_pos) * w1;
                  if (u_bone_count > 2 && w2 > 0.0) skinned_pos += transform_bone(2, in_pos) * w2;
                  if (u_bone_count > 3 && w3 > 0.0) skinned_pos += transform_bone(3, in_pos) * w3;
              } else {
                  skinned_pos = transform_bone(0, in_pos);
              }
          }

          float zoom = (u_view.z == 0.0) ? 1.0 : u_view.z;
          vec2 screen_pos = skinned_pos * zoom + u_view.xy;

          vec2 ndc = (screen_pos / u_resolution) * 2.0 - 1.0;
          float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
          ndc.y = ndc.y * flip;
          gl_Position = vec4(ndc, 0.0, 1.0);

          v_color = u_tint;
          v_uv = in_uv;
      }
    GLSL

    def self.shader
      @shader ||= Shader.new(SKINNED_VERTEX_SHADER, Shaders::DEFAULT_SPRITE_FRAGMENT)
    end

    attr_reader :image, :bones, :weight_map, :div_x, :div_y, :mesh, :x, :y, :anchor
    attr_accessor :z, :blend, :alpha, :color, :visible, :camera, :weight_mode

    # 初期化
    # - image:       描画するテクスチャ (Zenoo::Image)
    # - bones:       影響を与える Bone / Sprite の配列
    # - weight_map:  重み付け用 Zenoo::Image (省略時はボーン配置から自動生成)
    # - weight_mode: :auto (自動判定), :gradient (2ボーン白黒補間), :rgba (4色塗り分け), :chain (多関節チェーン補間)
    # - div_x, div_y: メッシュの横・縦分割数 (デフォルト: 16x16)
    # - x, y:        バインド時の画像の配置基準座標 (省略時は先頭ボーンのワールド座標、ボーンがなければ 0, 0)
    # - anchor:      画像の配置基準 (:top_left, :center, :center_left 等)
    def initialize(image,
                   bones: [],
                   weight_map: nil,
                   weight_mode: :auto,
                   div_x: 16,
                   div_y: 16,
                   x: nil,
                   y: nil,
                   anchor: :top_left,
                   z: 0.0,
                   blend: :alpha,
                   alpha: 255,
                   color: :white,
                   camera: true)
      @image = image
      @bones = Array(bones)
      @div_x = [div_x.to_i, 1].max
      @div_y = [div_y.to_i, 1].max
      @anchor = anchor
      @anchor_x, @anchor_y = Collision.parse_anchor(anchor)

      if x.nil? && y.nil? && !@bones.empty?
        @x = @bones[0].world_pivot_x
        @y = @bones[0].world_pivot_y
      else
        @x = (x || 0.0).to_f
        @y = (y || 0.0).to_f
      end

      @z = z.to_f
      @blend = blend || :alpha
      @alpha = alpha
      @color = color
      @visible = true
      @camera = camera.nil? ? true : camera
      @weight_mode_setting = weight_mode

      @bind_poses = []
      @bone_m_data = Array.new(MAX_BONES * 4, 0.0)
      @bone_t_data = Array.new(MAX_BONES * 4, 0.0)

      build_mesh
      bind!

      if weight_map
        self.weight_map = weight_map
      else
        generate_auto_weight_map!
      end
    end

    def x=(v)
      @x = v.to_f
      build_mesh
    end

    def y=(v)
      @y = v.to_f
      build_mesh
    end

    def anchor=(v)
      @anchor = v
      @anchor_x, @anchor_y = Collision.parse_anchor(v)
      build_mesh
    end

    # 重み画像の設定
    def weight_map=(img)
      @weight_map = img
      if @weight_map && @weight_map.is_a?(Image)
        @weight_map.texture_filter = :linear
      end
      resolve_weight_mode
    end

    # 現在のボーン群のワールド姿勢を「初期姿勢（バインドポーズ）」として記憶します
    def bind!
      @bind_poses.clear
      @bones.first(MAX_BONES).each do |b|
        wx = b.world_pivot_x
        wy = b.world_pivot_y
        sx = b.world_scale_x
        sy = b.world_scale_y
        cos_v = b.world_cos
        sin_v = b.world_sin

        inv_sx = sx.abs > 0.00001 ? (1.0 / sx) : 1.0
        inv_sy = sy.abs > 0.00001 ? (1.0 / sy) : 1.0

        # ワールド座標 P からボーンローカル座標 L への逆変換:
        # Lx = ((Px - wx) * cos + (Py - wy) * sin) / sx
        # Ly = (-(Px - wx) * sin + (Py - wy) * cos) / sy
        im00 = cos_v * inv_sx
        im01 = sin_v * inv_sx
        im10 = -sin_v * inv_sy
        im11 = cos_v * inv_sy
        itx  = -(im00 * wx + im01 * wy)
        ity  = -(im10 * wx + im11 * wy)

        @bind_poses << [im00, im01, im10, im11, itx, ity, wx, wy]
      end
      self
    end
    alias rebind! bind!

    # ボーン配置から自動で滑らかな重みマップ (Image) を生成
    def generate_auto_weight_map!(width: 64, height: 64)
      w = [width.to_i, 4].max
      h = [height.to_i, 4].max
      w_img = Image.new(w, h)

      bone_count = [@bones.length, MAX_BONES].min
      if bone_count <= 1
        w_img.clear(:white)
        @weight_map = w_img
        @resolved_weight_mode = 0
        return w_img
      end

      img_w = @image ? @image.width.to_f : 1.0
      img_h = @image ? @image.height.to_f : 1.0
      tl_x = @x - @anchor_x * img_w
      tl_y = @y - @anchor_y * img_h

      # 各ボーンの線分 [始点x, 始点y, 終点x, 終点y] を収集
      segments = @bones.first(bone_count).map do |b|
        ax = b.world_pivot_x
        ay = b.world_pivot_y
        tx, ty = b.respond_to?(:tip_world_pos) ? b.tip_world_pos : [ax, ay]
        [ax, ay, tx, ty]
      end

      # すべてのボーンが親子チェーンとして直列につながっているか、または2ボーンかを判定
      use_chain = (@weight_mode_setting == :chain) ||
                  (@weight_mode_setting == :gradient && bone_count == 2) ||
                  (@weight_mode_setting == :auto && (bone_count == 2 || bone_count > 4 || is_serial_chain?))

      if use_chain
        # 末端ボーンが length == 0 かつ子なしの場合は単なる先端マーカなのでスキニング対象から除外
        active_bones = bone_count
        if active_bones > 2
          last_b = @bones[active_bones - 1]
          if (!last_b.respond_to?(:length) || last_b.length <= 0.0001) && last_b.children.empty?
            active_bones -= 1
          end
        end

        h.times do |py|
          v = (py + 0.5) / h.to_f
          wy = tl_y + v * img_h
          w.times do |px|
            u = (px + 0.5) / w.to_f
            wx = tl_x + u * img_w

            # 各ボーン線分への最短距離に応じた逆距離加重で、連続ボーンインデックス (0.0 .. active_bones-1) を算出
            num = 0.0
            den = 0.0
            active_bones.times do |i|
              ax, ay, bx, by = segments[i]
              dx = bx - ax
              dy = by - ay
              len_sq = dx * dx + dy * dy
              if len_sq > 0.0001
                t = (((wx - ax) * dx + (wy - ay) * dy) / len_sq).clamp(0.0, 1.0)
                proj_x = ax + t * dx
                proj_y = ay + t * dy
              else
                proj_x = ax
                proj_y = ay
              end
              dist_sq = (wx - proj_x) * (wx - proj_x) + (wy - proj_y) * (wy - proj_y)
              wt = 1.0 / (dist_sq + 36.0)**2
              num += i.to_f * wt
              den += wt
            end

            val = (den > 0.0 && active_bones > 1) ? ((num / den) / (active_bones - 1).to_f).clamp(0.0, 1.0) : 0.0
            c = (val * 255.0).round.clamp(0, 255)
            w_img.raw_set_pixel_rgba(px, py, c, c, c, 255)
          end
        end
        w_img.sync
        w_img.texture_filter = :linear
        @weight_map = w_img
        @active_bone_count = active_bones
        @resolved_weight_mode = (active_bones == 2) ? 1 : 3
      else
        # RGBA 4ボーン逆距離ウェイトマップ
        segments4 = segments.first(4)

        h.times do |py|
          v = (py + 0.5) / h.to_f
          wy = tl_y + v * img_h
          w.times do |px|
            u = (px + 0.5) / w.to_f
            wx = tl_x + u * img_w

            weights = [0.0, 0.0, 0.0, 0.0]
            sum = 0.0
            segments4.each_with_index do |(ax, ay, bx, by), idx|
              dx = bx - ax
              dy = by - ay
              len_sq = dx * dx + dy * dy
              if len_sq > 0.0001
                t = (((wx - ax) * dx + (wy - ay) * dy) / len_sq).clamp(0.0, 1.0)
                proj_x = ax + t * dx
                proj_y = ay + t * dy
              else
                proj_x = ax
                proj_y = ay
              end
              dist_sq = (wx - proj_x) * (wx - proj_x) + (wy - proj_y) * (wy - proj_y)
              wt = 1.0 / (dist_sq + 25.0)**1.5
              weights[idx] = wt
              sum += wt
            end

            if sum > 0.0
              r = ((weights[0] / sum) * 255.0).round.clamp(0, 255)
              g = ((weights[1] / sum) * 255.0).round.clamp(0, 255)
              b = ((weights[2] / sum) * 255.0).round.clamp(0, 255)
              a = ((weights[3] / sum) * 255.0).round.clamp(0, 255)
            else
              r = 255; g = 0; b = 0; a = 0
            end
            w_img.raw_set_pixel_rgba(px, py, r, g, b, a)
          end
        end
        w_img.sync
        w_img.texture_filter = :linear
        @weight_map = w_img
        @active_bone_count = [bone_count, 4].min
        @resolved_weight_mode = 2
      end

      w_img
    end

    # 描画
    def draw(z: nil, blend: nil, shader: nil)
      return unless @visible && @image && @mesh

      update_bone_uniforms

      eff_z = z ? z.to_f : @z
      eff_blend = blend || @blend
      eff_shader = shader || self.class.shader

      # カメラ変換の取得
      cam = if @camera.is_a?(Camera)
              @camera
            elsif @camera
              Window.camera_enabled? ? Window.camera : nil
            else
              nil
            end
      if cam
        cz, cam_ox, cam_oy = cam.view
        view_vec = [cam_ox + Window.offset_x, cam_oy + Window.offset_y, cz, 0.0]
      else
        view_vec = [Window.offset_x, Window.offset_y, 1.0, 0.0]
      end

      # 乗算カラーとアルファ
      c_col = Backend.normalize_color(@color || :white)
      af = (@alpha ? @alpha.to_f / 255.0 : 1.0).clamp(0.0, 1.0)
      tint_vec = [c_col[0].to_f, c_col[1].to_f, c_col[2].to_f, c_col[3].to_f * af]

      w_uv = @weight_map ? @weight_map.uv : [0.0, 0.0, 1.0, 1.0]
      bone_count = @active_bone_count || [@bones.length, MAX_BONES].min

      uniforms = {
        u_weight_map: @weight_map,
        u_weight_uv_rect: w_uv,
        u_weight_mode: @resolved_weight_mode || 1,
        u_bone_count: bone_count,
        u_bone_m: @bone_m_packed,
        u_bone_t: @bone_t_packed,
        u_view: view_vec,
        u_tint: tint_vec
      }

      @mesh.draw(z: eff_z, blend: eff_blend, shader: eff_shader, image: @image, uniforms: uniforms)
    end

    private

    def is_serial_chain?
      return true if @bones.length <= 2
      (@bones.length - 1).times do |i|
        return false unless @bones[i + 1].parent.equal?(@bones[i])
      end
      true
    end

    def resolve_weight_mode
      bone_count = [@bones.length, MAX_BONES].min
      case @weight_mode_setting
      when :gradient
        @resolved_weight_mode = 1
      when :rgba
        @resolved_weight_mode = 2
      when :chain
        @resolved_weight_mode = 3
      else
        if bone_count <= 1
          @resolved_weight_mode = 0
        elsif bone_count == 2
          @resolved_weight_mode = 1
        elsif bone_count <= 4
          @resolved_weight_mode = 2
        else
          @resolved_weight_mode = 3
        end
      end
    end

    def update_bone_uniforms
      bone_count = [@bones.length, MAX_BONES].min
      i = 0
      while i < bone_count
        b = @bones[i]
        bp = @bind_poses[i]
        if bp
          im00, im01, im10, im11, itx, ity = bp
          wx = b.world_pivot_x
          wy = b.world_pivot_y
          sx = b.world_scale_x
          sy = b.world_scale_y
          cos_v = b.world_cos
          sin_v = b.world_sin

          # 現在のボーンローカル -> ワールド変換行列 W:
          # Wx = sx * cos * Lx - sy * sin * Ly + wx
          # Wy = sx * sin * Lx + sy * cos * Ly + wy
          wm00 = sx * cos_v
          wm01 = -sy * sin_v
          wm10 = sx * sin_v
          wm11 = sy * cos_v

          # 合成変換 M = W * InvBind:
          m00 = wm00 * im00 + wm01 * im10
          m01 = wm00 * im01 + wm01 * im11
          m10 = wm10 * im00 + wm11 * im10
          m11 = wm10 * im01 + wm11 * im11
          tx  = wm00 * itx  + wm01 * ity + wx
          ty  = wm10 * itx  + wm11 * ity + wy

          base = i * 4
          @bone_m_data[base]     = m00
          @bone_m_data[base + 1] = m01
          @bone_m_data[base + 2] = m10
          @bone_m_data[base + 3] = m11

          @bone_t_data[base]     = tx
          @bone_t_data[base + 1] = ty
          @bone_t_data[base + 2] = 0.0
          @bone_t_data[base + 3] = 0.0
        end
        i += 1
      end

      @bone_m_packed = @bone_m_data.pack("f*")
      @bone_t_packed = @bone_t_data.pack("f*")
    end

    # 画像を div_x × div_y の格子状三角形メッシュに分割してバイナリ構築
    # 頂点レイアウト: POS2_UV2_COLOR4 (8 floats/vertex)
    # ※ color.xy に正規化ローカルUV (0.0 .. 1.0) を格納し、weight_map のサンプリングに使用
    def build_mesh
      return unless @image

      img_w = @image.width.to_f
      img_h = @image.height.to_f
      u0, v0, uw, vh = @image.uv

      tl_x = @x - @anchor_x * img_w
      tl_y = @y - @anchor_y * img_h

      nx = @div_x
      ny = @div_y
      inv_nx = 1.0 / nx.to_f
      inv_ny = 1.0 / ny.to_f

      verts = []
      ny.times do |iy|
        ty0 = iy * inv_ny
        ty1 = (iy + 1) * inv_ny
        py0 = tl_y + ty0 * img_h
        py1 = tl_y + ty1 * img_h
        tv0 = v0 + ty0 * vh
        tv1 = v0 + ty1 * vh

        nx.times do |ix|
          tx0 = ix * inv_nx
          tx1 = (ix + 1) * inv_nx
          px0 = tl_x + tx0 * img_w
          px1 = tl_x + tx1 * img_w
          tu0 = u0 + tx0 * uw
          tu1 = u0 + tx1 * uw

          # Triangle 1: (0,0) -> (0,1) -> (1,0)
          verts.push(
            px0, py0, tu0, tv0, tx0, ty0, 1.0, 1.0,
            px0, py1, tu0, tv1, tx0, ty1, 1.0, 1.0,
            px1, py0, tu1, tv0, tx1, ty0, 1.0, 1.0,
            # Triangle 2: (1,0) -> (0,1) -> (1,1)
            px1, py0, tu1, tv0, tx1, ty0, 1.0, 1.0,
            px0, py1, tu0, tv1, tx0, ty1, 1.0, 1.0,
            px1, py1, tu1, tv1, tx1, ty1, 1.0, 1.0
          )
        end
      end

      total_vertices = nx * ny * 6
      @mesh = Mesh.new(
        data: verts.pack("f*"),
        count: total_vertices,
        pipeline: :textured_triangles,
        image: @image,
        shader: self.class.shader,
        blend: @blend
      )
    end
  end
end
