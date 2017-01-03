//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Clutter;
using Meta;

namespace Gala
{
	/**
	 * Container which controls the layout of a set of window clones. The clones will be placed in
	 * their real position with scaled size.
	 */
	public class DeepinWindowThumbContainer : DeepinWindowBaseContainer
	{
		const int WINDOW_OPACITY_SELECTED = 255;
		const int WINDOW_OPACITY_UNSELECTED = 200;

		int padding_top { get; set; default = 6; }
		int padding_left { get; set; default = 6; }
		int padding_right { get; set; default = 6; }
		int padding_bottom { get; set; default = 6; }

		public DeepinWindowThumbContainer (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		/**
		 * {@inheritDoc}
		 */
		public override void do_select_clone (DeepinWindowClone window_clone, bool select,
											  bool animate = true)
		{
			window_clone.save_easing_state ();

			window_clone.set_easing_duration (animate ? DeepinWindowClone.LAYOUT_DURATION : 0);
			window_clone.set_easing_mode (DeepinWindowClone.LAYOUT_MODE);

			if (select) {
				set_child_at_index (window_clone, -1);
				window_clone.opacity = WINDOW_OPACITY_SELECTED;
			} else {
				window_clone.opacity = WINDOW_OPACITY_UNSELECTED;
			}

			window_clone.restore_easing_state ();
		}

		/**
		 * {@inheritDoc}
		 */
		public override DeepinWindowClone? add_window (Window window, bool thumbnail_mode = false)
		{
			return base.add_window (window, true);
		}

		/**
		 * {@inheritDoc}
		 */
		public override void relayout (bool selecting = false)
		{

            var screen = workspace.get_screen ();
            if (screen.get_n_monitors () == 0) {
                /* this happens during the changing of monitors */
                return;
            }

			foreach (var child in get_children ()) {
				var window_clone = child as DeepinWindowClone;
				var box = get_layout_box_for_window (window_clone);
				var rect = DeepinUtils.new_rect_for_actor_box (box);
				window_clone.take_slot (rect);
			}
		}

		public void splay_windows ()
		{
            if (get_children ().length() < 1)
                return;

			var windows = new List <InternalUtils.TilableWindow?> ();
			foreach (var child in get_children ()) {
				unowned DeepinWindowClone window_clone = (DeepinWindowClone)child;
				windows.prepend ({ window_clone.window.get_frame_rect (), window_clone });
			}

			// make sure the windows are always in the same order so the algorithm doesn't give us
			// different slots based on stacking order, which can lead to windows flying around
			// weirdly
			windows.sort ((a, b) => {
				var seq_a = (a.id as DeepinWindowClone).window.get_stable_sequence ();
				var seq_b = (b.id as DeepinWindowClone).window.get_stable_sequence ();
				return (int)(seq_b - seq_a);
			});

			Meta.Rectangle area = { padding_left, padding_top,
									(int)width - padding_left - padding_right,
									(int)height - padding_top - padding_bottom };

            var window_positions = InternalUtils.calculate_grid_placement (area, windows, false);

            foreach (var tilable in window_positions) {
                var window_clone = tilable.id as DeepinWindowClone;
                window_clone.take_slot (tilable.rect);
            }
		}

        /* move window into target monitor and then translate it into 
         * logical monitor which is positioned at (0,0)
          */
        void shove_into_primary(Meta.Rectangle geom, ref Meta.Rectangle rect)
        {
            if (rect.x >= geom.x + geom.width) rect.x -= geom.x + geom.width;
            else if (rect.x < geom.x) rect.x += geom.x;
            if (rect.y >= geom.y + geom.width) rect.y -= geom.y + geom.height;
            else if (rect.y < geom.y) rect.y += geom.y;

            if (rect.x >= geom.x) rect.x -= geom.x;
            if (rect.y >= geom.y) rect.y -= geom.y;
        }

		/**
		 * {@inheritDoc}
		 */
		public override ActorBox get_layout_box_for_window (DeepinWindowClone window_clone)
		{
            Meta.Screen screen;
			float thumb_width, thumb_height;

            screen = workspace.get_screen ();
			DeepinWorkspaceThumbContainer.get_prefer_thumb_size (screen,
																 out thumb_width, out thumb_height);

			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);
			float scale = thumb_width != 0 ? thumb_width / (float)monitor_geom.width : 0.5f;

			Meta.Rectangle rect;
			rect = window_clone.window.get_frame_rect ();
            shove_into_primary(monitor_geom, ref rect);

			var box = DeepinUtils.new_actor_box_for_rect (rect);

			// make window rectangle center of monitor to avoid affect by _NET_WM_STRUT_PARTIAL
			// which set by dock window
			if (!window_clone.window.is_fullscreen ()) {
				Meta.Rectangle work_area;
                // window's monitor could larger than available monitors, this happens during
                // monitors-changed handler: every window are updating their monitor infos and emit 
                // window-left-monitor signals. each window-left-monitor is triggering relayout
                // before all of the windows will have finished their monitor infos.
				 if (window_clone.window.get_monitor () >= screen.get_n_monitors ()) {
                     work_area = window_clone.window.get_work_area_for_monitor (screen.get_primary_monitor ());
                 } else {
                     work_area = window_clone.window.get_work_area_current_monitor ();
                 }
				float offset_x = (float)(monitor_geom.width - work_area.width) / 2;
				float offset_y = (float)(monitor_geom.height - work_area.height) / 2;
				DeepinUtils.offset_actor_box (ref box, offset_x, offset_y);
			}

			DeepinUtils.scale_actor_box (ref box, scale);
			DeepinUtils.scale_actor_box_in_center (ref box, 0.9f);

			return box;
		}


		/**
		 * Adjust window clone's opacity when opened.
		 */
		public virtual void open (Window? focus_window = null)
		{
			base.open ();

			foreach (var child in get_children ()) {
				if ((child as DeepinWindowClone).window == focus_window) {
					child.opacity = WINDOW_OPACITY_SELECTED;
				} else {
					child.opacity = WINDOW_OPACITY_UNSELECTED;
				}
			}
		}
	}
}
