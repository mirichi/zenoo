# frozen_string_literal: true

require_relative 'sprite'

module Zenoo
  # 剛体物理パラメータと応答メソッドを備えたスプライト基底クラス
  class PhysicsSprite < Sprite
    attr_accessor :vx, :vy, :omega, :mass, :inertia, :restitution, :friction

    def initialize(x = 0.0, y = 0.0, image = nil,
                   vx: 0.0, vy: 0.0, omega: 0.0,
                   mass: 1.0, inertia: nil,
                   restitution: 0.3, friction: 0.5,
                   anchor: :center, pivot: :center, **kwargs)
      super(x, y, image, anchor: anchor, pivot: pivot, **kwargs)
      @vx = vx.to_f
      @vy = vy.to_f
      @omega = omega.to_f
      @mass = mass.to_f
      @inertia = inertia ? inertia.to_f : nil
      @restitution = restitution.to_f
      @friction = friction.to_f
    end

    # 逆質量 (1 / mass)
    def inv_mass
      @mass > 0.00001 ? 1.0 / @mass : 0.0
    end

    # 逆慣性モーメント (1 / inertia)
    def inv_inertia
      inert = @inertia || Physics.inertia_of(collider, mass: @mass)
      inert > 0.00001 ? 1.0 / inert : 0.0
    end

    # 静的障害物との衝突物理応答を計算し、自身に即時反映
    def resolve_static(hit, static_body = nil, **kwargs)
      res = Physics.resolve_static(hit, self, static_body, **kwargs)
      res&.apply_to(self)
      res
    end

    # 別の動的物体との2体衝突物理応答を計算し、双方に即時反映
    def resolve_collision(hit, other_body, **kwargs)
      res = Physics.resolve(hit, self, other_body, **kwargs)
      res&.apply_to(self, other_body)
      res
    end

    # ====================================================
    # 座標変換ヘルパー
    # ====================================================

    # 自身のローカル座標 [lx, ly] を現在のワールド座標 [wx, wy] に変換
    def local_to_world(lx, ly)
      Physics.local_to_world(self, lx, ly)
    end

    # ワールド座標 [wx, wy] を自身の現在のローカル座標 [lx, ly] に変換
    def world_to_local(wx, wy)
      Physics.world_to_local(self, wx, wy)
    end

    # 相手スプライトとの現在の相対オフセット [ox, oy] と角度差 (deg) を計算
    def relative_offset(other_sprite)
      Physics.relative_offset(self, other_sprite)
    end

    # ====================================================
    # 拘束ショートカット
    # ====================================================

    # 目標点 / マウスへの引っ張り拘束
    def constrain_point(tx, ty, anchor: nil, **kwargs)
      Physics.constrain_point(self, tx, ty, anchor: anchor, **kwargs)
    end

    def constrain_mouse(mx, my, **kwargs)
      Physics.constrain_mouse(self, mx, my, **kwargs)
    end

    # 相手物体（または固定点）とのピン結合
    def constrain_pin(other = nil, pivot: nil, anchor: nil, other_anchor: nil)
      Physics.constrain_pin(self, other, pivot: pivot, anchor_a: anchor, anchor_b: other_anchor)
    end

    # 相手物体との完全固定 (溶接 / リジッド結合)
    def constrain_weld(other, offset: nil, angle: nil, **kwargs)
      Physics.constrain_weld(self, other, offset: offset, angle: angle, **kwargs)
    end

    # 相手物体との距離拘束 (ロッド / ロープ)
    def constrain_distance(other, length: nil, min: nil, max: nil, anchor: nil, other_anchor: nil)
      Physics.constrain_distance(self, other, length: length, min: min, max: max, anchor_a: anchor, anchor_b: other_anchor)
    end
  end

  module Physics
    Sprite = Zenoo::PhysicsSprite
  end
end
