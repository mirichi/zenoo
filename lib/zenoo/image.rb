class Zenoo::Image
  # オフスクリーンFBO描画ブロック
  # Image.render_to(canvas) do
  #   Window.draw_card(...)
  # end
  def self.render_to(target, &block)
    Zenoo::Window.with_target(target, &block)
  end

  def command_pool
    @command_pool ||= []
  end

  def queue_count
    @queue_count ||= 0
  end

  def has_pending_draws?
    @queue_count && @queue_count > 0
  end

  def enqueue_draw(z, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms = nil, blend = 0)
    pool = command_pool
    cmd = nil
    if queue_count < pool.length
      cmd = pool[@queue_count]
    else
      cmd = Zenoo::Window::DrawCommand.new
      pool.push(cmd)
    end
    zf = z.to_f
    @needs_z_sort = true if zf != 0.0
    cmd.set(self, zf, @queue_count, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms, blend)
    @queue_count += 1
    Zenoo::Window.register_pending_image(self)
  end

  def sort_draw_queue
    return unless @needs_z_sort
    return if queue_count <= 1

    pool = command_pool
    i = 1
    while i < @queue_count
      target_cmd = pool[i]
      tz = target_cmd.z
      j = i - 1
      while j >= 0
        prev_cmd = pool[j]
        break if prev_cmd.z <= tz
        pool[j + 1] = prev_cmd
        j -= 1
      end
      pool[j + 1] = target_cmd
      i += 1
    end
  end

  def flush_draw_queue
    return if @is_flushing # 再帰 / 自己参照ガード
    return unless has_pending_draws?

    @is_flushing = true
    sort_draw_queue

    # 直前のレンダーターゲットを退避して自身をセット
    old_target = Zenoo::Window.active_gl_target
    set_as_render_target
    Zenoo::Window.active_gl_target = self

    pool = command_pool
    count = @queue_count

    Zenoo::Window.execute_commands(pool, count)

    @queue_count = 0
    @needs_z_sort = false
    @is_flushing = false

    # 直前のレンダーターゲットに復元
    if old_target
      old_target.set_as_render_target
    else
      Zenoo::Native::Image.reset_render_target
    end
    Zenoo::Window.active_gl_target = old_target
  end
end
