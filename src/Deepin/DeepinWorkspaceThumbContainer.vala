//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//  Copyright (C) 2014 Tom Beckmann
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
	 * Will be put at end of workspace thumbnail list in DeepinMultitaskingView if number less than
	 * MAX_WORKSPACE_NUM.
	 */
	class DeepinWorkspaceAddButton : DeepinCssStaticActor
	{
		const double PLUS_SIZE = 45.0;
		const double PLUS_LINE_WIDTH = 2.0;

		Gdk.RGBA color;

		public DeepinWorkspaceAddButton ()
		{
			base ("deepin-workspace-add-button");
		}

		construct
		{
			color = DeepinUtils.get_css_color_gdk_rgba (style_class);

			(content as Canvas).draw.connect (on_draw_content);
		}

		bool on_draw_content (Cairo.Context cr, int width, int height)
		{
			// draw tha plus button
			cr.move_to (width / 2 - PLUS_SIZE / 2, height / 2);
			cr.line_to (width / 2 + PLUS_SIZE / 2, height / 2);

			cr.move_to (width / 2, height / 2 - PLUS_SIZE / 2);
			cr.line_to (width / 2, height / 2 + PLUS_SIZE / 2);

			cr.set_line_width (PLUS_LINE_WIDTH);
			cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
			cr.stroke_preserve ();

			return false;
		}
	}

	/**
	 * This class contains the DeepinWorkspaceThumbClone which placed in the top of multitaskingview
	 * and will take care of displaying actors for inserting windows between the groups once
	 * implemented.
	 */
	public class DeepinWorkspaceThumbContainer : Actor
	{
		/**
		 * The percent value between thumbnail workspace clone's width and monitor's width.
		 */
		public const float WORKSPACE_WIDTH_PERCENT = 0.12f;

		const int PLUS_FADE_IN_DURATION = 700;

		public signal void workspace_closing (Workspace workspace);
		/**
		 * The percent value between distance of thumbnail workspace clones and monitor's width.
		 */
		const float SPACING_PERCENT = 0.02f;

		const int LAYOUT_DURATION = 800;

		public Screen screen { get; construct; }

		Actor plus_button;

		int new_workspace_index_by_manual = -1;

		public DeepinWorkspaceThumbContainer (Screen screen)
		{
			Object (screen: screen);
		}

		construct
		{
			plus_button = new DeepinWorkspaceAddButton ();
			plus_button.reactive = true;
			plus_button.set_pivot_point (0.5f, 0.5f);
			plus_button.button_press_event.connect (() => {
				append_new_workspace ();
				return false;
			});

			append_plus_button_if_need ();

			actor_removed.connect (on_actor_removed);

			screen.monitors_changed.connect (relayout);
		}

		~DeepinWorkspaceThumbContainer ()
		{
			screen.monitors_changed.disconnect (relayout);
		}

		public void append_new_workspace ()
		{
			DeepinUtils.start_fade_out_animation (plus_button,
												  DeepinMultitaskingView.WORKSPACE_FADE_DURATION,
												  DeepinMultitaskingView.WORKSPACE_FADE_MODE,
												  () => {
			 	remove_child (plus_button);
				new_workspace_index_by_manual = Prefs.get_num_workspaces ();
				DeepinUtils.append_new_workspace (screen);
			});
		}

		public void open ()
		{
			append_plus_button_if_need ();
		}

		public void close ()
		{
			append_plus_button_if_need ();
		}

		public void add_workspace (DeepinWorkspaceThumbClone workspace_clone,
								   DeepinUtils.PlainCallback? cb = null)
		{
			var index = workspace_clone.workspace.index ();
			insert_child_at_index (workspace_clone, index);
			place_child (workspace_clone, index, false);
			select_workspace (workspace_clone.workspace.index (), true);

			workspace_clone.start_fade_in_animation ();

			// if workspace is added manually, set workspace name field editable
			if (workspace_clone.workspace.index () == new_workspace_index_by_manual) {
				// since workspace name field grab key focus, other actors could not catch mouse
				// leave_event, so we hide close button manually
				hide_workspace_close_button ();

				new_workspace_index_by_manual = -1;

                enable_workspace_drag_action ();
                append_plus_button_if_need ();
                DeepinUtils.switch_to_workspace (workspace_clone.workspace.get_screen (),
                        workspace_clone.workspace.index ());
                if (cb != null) {
                    cb ();
                }
                // or else
                //select_workspace (screen.get_active_workspace_index (), true);
			}

			workspace_clone.closing.connect (on_workspace_closing);

			relayout ();
		}

		public void remove_workspace (DeepinWorkspaceThumbClone workspace_clone)
		{
			workspace_clone.closing.disconnect (on_workspace_closing);

			remove_child (workspace_clone);

			append_plus_button_if_need ();

			relayout ();
		}

		void on_workspace_closing (DeepinWorkspaceThumbClone thumb_workspace)
		{
			workspace_closing (thumb_workspace.workspace);

			// workspace is closing, disable the dragging actions
			disable_workspace_drag_action ();
		}

		void on_actor_removed (Clutter.Actor actor)
		{
			// workspace removed and close animation finished, enable the dragging actions
			enable_workspace_drag_action ();
		}

		void enable_workspace_drag_action ()
		{
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).enable_drag_action ();
				}
			}
		}

		void disable_workspace_drag_action ()
		{
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).disable_drag_action ();
				}
			}
		}

		void hide_workspace_close_button ()
		{
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).thumb_clone.show_close_button (false);
				}
			}
		}

		/**
		 * Make plus button visible if workspace number less than MAX_WORKSPACE_NUM.
		 */
		void append_plus_button_if_need ()
		{
			if (could_append_plus_button ()) {
				plus_button.opacity = 0;
				add_child (plus_button);
				place_child (plus_button, get_n_children () - 1, false);
				DeepinUtils.start_fade_in_back_animation (plus_button, PLUS_FADE_IN_DURATION);

				relayout ();
			}
		}

		bool could_append_plus_button ()
		{
			if (Prefs.get_num_workspaces () < WindowManagerGala.MAX_WORKSPACE_NUM &&
				!contains (plus_button)) {
				return true;
			}
			return false;
		}

		public void relayout ()
		{
			var i = 0;
			foreach (var child in get_children ()) {
				place_child (child, i);
				i++;
			}
		}

		public void select_workspace (int index, bool animate)
		{
			foreach (var child in get_children ()) {
				if (child is DeepinWorkspaceThumbClone) {
					var thumb_workspace = child as DeepinWorkspaceThumbClone;
					if (thumb_workspace.workspace.index () == index) {
						thumb_workspace.set_select (true, animate);
					} else {
						thumb_workspace.set_select (false, animate);
					}
				}
			}
		}

		public static void get_prefer_thumb_size (Screen screen, out float width, out float height)
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			// calculate monitor width height ratio
			float monitor_whr = (float)monitor_geom.height / monitor_geom.width;

			width = monitor_geom.width * WORKSPACE_WIDTH_PERCENT;
			height = width * monitor_whr;
		}

		ActorBox get_child_layout_box (Screen screen, int index, bool is_thumb_clone = false)
		{
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			var box = ActorBox ();

			float child_x = 0, child_y = 0;
			float child_width = 0, child_height = 0;
			float child_spacing = monitor_geom.width * SPACING_PERCENT;

			get_prefer_thumb_size (screen, out child_width, out child_height);
			child_x = (child_width + child_spacing) * index;

			// place child center of monitor
			float container_width = child_width * get_n_children () + child_spacing * (get_n_children () - 1);
			float offset_x = ((float)monitor_geom.width - container_width) / 2;
			child_x += offset_x;

			box.set_size (child_width, child_height);
			box.set_origin (child_x, child_y);

			return box;
		}

		void place_child (Actor child, int index, bool animate = true)
		{
			ActorBox child_box = get_child_layout_box (screen, index,
													   child is DeepinWorkspaceThumbClone);
			child.width = child_box.get_width ();
			child.height = child_box.get_height ();

			if (animate) {
				// workspace is relayout, disable the drag action
				if (child is DeepinWorkspaceThumbClone) {
					(child as DeepinWorkspaceThumbClone).disable_drag_action ();
				}

				var position = Point.alloc ();
				position.x = child_box.get_x ();
				position.y = child_box.get_y ();
				var position_value = GLib.Value (typeof (Point));
				position_value.set_boxed (position);
				DeepinUtils.start_animation_group (child, "thumb-workspace-slot", LAYOUT_DURATION,
												   DeepinUtils.clutter_set_mode_bezier_out_back,
												   "position", &position_value);

				// enable the drag action after workspace relayout when plus button will not be
				// append later, which will queue relayout again
				if (child is DeepinWorkspaceThumbClone && !could_append_plus_button ()) {
					var thumb_clone = child as DeepinWorkspaceThumbClone;
					DeepinUtils.run_clutter_callback (thumb_clone, "thumb-workspace-slot", thumb_clone.enable_drag_action);
				}
			} else {
				child.x = child_box.get_x ();
				child.y = child_box.get_y ();
			}
		}
	}
}
