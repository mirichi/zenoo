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
  end

  module Physics
    Sprite = Zenoo::PhysicsSprite
  end
end
