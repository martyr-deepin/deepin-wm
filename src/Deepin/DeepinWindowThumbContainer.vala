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
		const int WINDOW_OPACITY_UNSELECTED = 150;

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
			foreach (var child in get_children ()) {
				var window_clone = child as DeepinWindowClone;
				var box = get_layout_box_for_window (window_clone);
				var rect = DeepinUtils.new_rect_for_actor_box (box);
				window_clone.take_slot (rect);
			}
		}

		/**
		 * {@inheritDoc}
		 */
		public override ActorBox get_layout_box_for_window (DeepinWindowClone window_clone)
		{
			float thumb_width, thumb_height;
			DeepinWorkspaceThumbContainer.get_prefer_thumb_size (workspace.get_screen (),
																 out thumb_width, out thumb_height);

			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());
			float scale = thumb_width != 0 ? thumb_width / (float)monitor_geom.width : 0.5f;

			Meta.Rectangle rect;
#if HAS_MUTTER312
			rect = window_clone.window.get_frame_rect ();
#else
			rect = window_clone.window.get_outer_rect ();
#endif

			var box = DeepinUtils.new_actor_box_for_rect (rect);

			// make window rectangle center of monitor to avoid affect by _NET_WM_STRUT_PARTIAL
			// which set by dock window
			if (!window_clone.window.is_fullscreen ()) {
				Meta.Rectangle work_area = window_clone.window.get_work_area_current_monitor ();
				float offset_x = (float)(monitor_geom.width - work_area.width) / 2;
				float offset_y = (float)(monitor_geom.height - work_area.height) / 2;
				DeepinUtils.offset_actor_box (ref box, offset_x, offset_y);
			}

			DeepinUtils.scale_actor_box (ref box, scale);
			DeepinUtils.scale_actor_box_in_center (ref box, 0.9f);

			return box;
		}
	}
}
