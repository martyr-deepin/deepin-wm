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

using Meta;
using Clutter;

namespace Gala
{
	public class DeepinWindowSnapshotContainer : Actor
	{
		public Workspace workspace { get; construct; }

		/**
		 * Mark if multitasking view opend.
		 */
		internal bool opened = false;


		public DeepinWindowSnapshotContainer (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			var windows = workspace.list_windows ();
            
			foreach (var window in windows) {
				if (window.window_type == WindowType.NORMAL && !window.on_all_workspaces) {
					add_window (window);
                } else if (window.window_type == WindowType.DOCK) {
					add_window (window);
                }
			}

			restack_windows (workspace.get_screen ());
            relayout ();
		}

		~DeepinWindowSnapshotContainer ()
		{
		}

		public virtual DeepinWindowClone? add_window (Window window, bool thumbnail_mode = true)
		{
			var new_window = new DeepinWindowClone (window, thumbnail_mode);
            new_window.reactive = false;
			new_window.destroy.connect (on_window_destroyed);
            add_child (new_window);

			return new_window;
		}

		void on_window_destroyed (Actor actor)
		{
			var window = actor as DeepinWindowClone;
			if (window == null) {
				return;
			}

			window.destroy.disconnect (on_window_destroyed);
		}

		/**
		 * Sort the windows z-order by their actual stacking to make intersections during animations
		 * correct.
		 */
		public virtual void restack_windows (Screen screen)
		{
			var display = screen.get_display ();
			var children = get_children ();

			var windows = new GLib.SList<unowned Meta.Window> ();
			foreach (var child in children) {
				var window_clone = child as DeepinWindowClone;
				windows.prepend (window_clone.window);
			}

			var windows_ordered = display.sort_windows_by_stacking (windows);

			int i = 0;
			foreach (var window in windows_ordered) {
				foreach (var child in children) {
					if ((child as DeepinWindowClone).window == window) {
						set_child_at_index (child, i);
						children.remove (child);
						break;
					}
				}
				i++;
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

		public ActorBox get_layout_box_for_window (DeepinWindowClone window_clone)
		{
            Meta.Screen screen;
			float thumb_width, thumb_height;

            screen = workspace.get_screen ();
			var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

			float scale = DeepinWorkspaceIndicator.WORKSPACE_SCALE;
            thumb_width = monitor_geom.width * scale;
            thumb_height = monitor_geom.height * scale;

			Meta.Rectangle rect;
			rect = window_clone.window.get_frame_rect ();
            shove_into_primary(monitor_geom, ref rect);

			var box = DeepinUtils.new_actor_box_for_rect (rect);

			DeepinUtils.scale_actor_box (ref box, scale);

			return box;
		}
        
		public void relayout ()
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
				window_clone.take_slot (rect, false);
			}
		}

		public virtual void open ()
		{
			if (opened) {
				return;
			}

			opened = true;

			restack_windows (workspace.get_screen ());
		}

		public virtual void close ()
		{
			if (!opened) {
				return;
			}

			opened = false;
		}
	}

    public class DeepinWorkspaceSnapshot: Actor
    {
        public Workspace workspace { get; construct; }

        public DeepinWindowSnapshotContainer window_container;

        // selected shape for workspace thumbnail clone
        Actor thumb_shape;
        Actor thumb_shape_selected;

        Actor workspace_shadow;
        Actor workspace_clone;

        DeepinFramedBackground background;

        public DeepinWorkspaceSnapshot (Workspace workspace)
        {
            Object (workspace: workspace);
        }

        construct
        {
            workspace_shadow = new Actor ();
            workspace_shadow.add_effect_with_name (
                    "shadow", new ShadowEffect (get_thumb_workspace_prefer_width (),
                        get_thumb_workspace_prefer_heigth (), 10, 0, 25, 3));
            add_child (workspace_shadow);

            workspace.get_screen ().monitors_changed.connect (update_workspace_shadow);

            thumb_shape =
                new DeepinCssStaticActor ("deepin-workspace-thumb-clone", Gtk.StateFlags.NORMAL);
            thumb_shape.set_pivot_point (0.5f, 0.5f);

            // selected shape for workspace thumbnail clone
            thumb_shape_selected =
                new DeepinCssStaticActor ("deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
            thumb_shape_selected.opacity = 0;
            thumb_shape_selected.set_pivot_point (0.5f, 0.5f);
            add_child (thumb_shape);

            // workspace thumbnail clone
            workspace_clone = new Actor ();
            workspace_clone.set_pivot_point (0.5f, 0.5f);

            background = new DeepinFramedBackground (workspace.get_screen (), workspace.index (), 
                    false, false, DeepinWorkspaceIndicator.WORKSPACE_SCALE);
            background.set_rounded_radius (6);
            workspace_clone.add_child (background);

            window_container = new DeepinWindowSnapshotContainer (workspace);
            workspace_clone.add_child (window_container);

            int radius = DeepinUtils.get_css_border_radius ("deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
            window_container.add_effect (new DeepinRoundRectEffect (radius));

            add_child (workspace_clone);
            add_child (thumb_shape_selected);
        }

        ~DeepinWorkspaceSnapshot ()
        {
            workspace.get_screen ().monitors_changed.disconnect (update_workspace_shadow);
            background.destroy ();
        }

        public void set_select (bool value, bool animate = true)
        {
            int duration = animate ? DeepinMultitaskingView.WORKSPACE_SWITCH_DURATION : 0;

            thumb_shape.visible = !value;

            // selected shape for workspace thumbnail clone
            thumb_shape_selected.save_easing_state ();

            thumb_shape_selected.set_easing_duration (duration);
            thumb_shape_selected.set_easing_mode (AnimationMode.LINEAR);
            thumb_shape_selected.opacity = value ? 255 : 0;

            thumb_shape_selected.restore_easing_state ();
            queue_redraw ();
        }

        void update_workspace_shadow ()
        {
            var shadow_effect = workspace_shadow.get_effect ("shadow") as ShadowEffect;
            if (shadow_effect != null) {
                shadow_effect.update_size (
                        get_thumb_workspace_prefer_width (), get_thumb_workspace_prefer_heigth ());
            }
        }

        int get_thumb_workspace_prefer_width ()
        {
            var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());
            return (int)(monitor_geom.width * DeepinWorkspaceIndicator.WORKSPACE_SCALE);
        }

        int get_thumb_workspace_prefer_heigth ()
        {
            var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());
            return (int)(monitor_geom.height * DeepinWorkspaceIndicator.WORKSPACE_SCALE);
        }

        public override void allocate (ActorBox box, AllocationFlags flags)
        {
            base.allocate (box, flags);

            var monitor_geom = DeepinUtils.get_primary_monitor_geometry (workspace.get_screen ());

            // allocate workspace clone
            var thumb_box = ActorBox ();
            float thumb_width = box.get_width ();
            float thumb_height = box.get_height ();
            thumb_box.set_size (thumb_width, thumb_height);
            thumb_box.set_origin (0, 0);
            workspace_clone.allocate (thumb_box, flags);
            workspace_shadow.allocate (thumb_box, flags);
            window_container.allocate (thumb_box, flags);

            background.set_size (box.get_width (), box.get_height ());

			var thumb_shape_box = ActorBox ();
			thumb_shape_box.set_size (thumb_width+2, thumb_height+2);
			thumb_shape_box.set_origin (-1, -1);
			thumb_shape.allocate (thumb_shape_box, flags);

            thumb_shape_box.set_size (thumb_width+6, thumb_height+6);
            thumb_shape_box.set_origin (-3, -3);
            thumb_shape_selected.allocate (thumb_shape_box, flags);
        }
    }

    /**
     * This class contains the DeepinWorkspaceThumbClone which placed in the top of multitaskingview
     * and will take care of displaying actors for inserting windows between the groups once
     * implemented.
     */
    public class DeepinWorkspaceIndicator : Actor
    {
        public const float WORKSPACE_SCALE = 0.10f;

        /**
         * The distance measure in percentage of the monitor width between workspaces
         */
        public const float SPACING_PERCENT = 0.0156f;

        public const int MARGIN_HORIZONTAL = 22;
        public const int MARGIN_VERTICAL   = 21;

        int POPUP_TIMEOUT = 2000;

		public WindowManager wm { get; construct; }
        public Screen screen { get; construct; }

        Actor popup_border;
        Actor popup_lighter;
		Actor popup;
        BlurActor background;

        uint popup_timeout_id = 0;

        //caches
        Meta.Rectangle monitor_geom;

        public DeepinWorkspaceIndicator (WindowManager wm, Screen screen)
        {
            Object (wm: wm, screen: screen);
        }

        construct
        {
            screen.monitors_changed.connect (relayout);
            
            monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

            popup_border =
                new DeepinCssStaticActor ("deepin-workspace-indicator-border", Gtk.StateFlags.NORMAL);
            popup_border.set_pivot_point (0.5f, 0.5f);

            popup_lighter =
                new DeepinCssStaticActor ("deepin-workspace-indicator-lighter", Gtk.StateFlags.NORMAL);
            popup_lighter.set_pivot_point (0.5f, 0.5f);

            popup = new DeepinCssStaticActor ("deepin-workspace-indicator");

            background = new BlurActor (screen);
            background.set_radius (13);

            add_child (background);
            add_child (popup_lighter);
            add_child (popup_border);
            add_child (popup);
        }

        ~DeepinWorkspaceIndicator ()
        {
            screen.monitors_changed.disconnect (relayout);
            if (popup_timeout_id != 0) {
                Source.remove (popup_timeout_id);
            }
        }

        void start_timer ()
        {
            if (popup_timeout_id != 0) {
                Source.remove (popup_timeout_id);
                popup_timeout_id = 0;
            }

            popup_timeout_id = Timeout.add (POPUP_TIMEOUT, () => {
                    close ();
                    popup_timeout_id = 0;
                    return false;
            });
        }

        Cairo.Region? last_region = null;
        public void open ()
        {
            POPUP_TIMEOUT = AnimationSettings.get_default ().workspace_popup_duration;

            if (!visible) {
                foreach (var workspace in screen.get_workspaces ()) {
                    var snapshot = new DeepinWorkspaceSnapshot (workspace);
                    popup.add_child (snapshot);
                }
                relayout ();
                float x = Math.floorf(popup.x);
                float y = Math.floorf(popup.y);
                float w = Math.floorf(popup.width);
                float h = Math.floorf(popup.height);

                background.set_position (x, y);
                background.set_size (w, h);

                popup_border.set_position (x-1, y-1);
                popup_border.set_size (w+2, h+2);

                popup_lighter.set_position (x, y);
                popup_lighter.set_size (w, h);

                Cairo.RectangleInt r =  {0, 0, (int)w, (int)h};
                Cairo.RectangleInt[] rects = { r };
                int[] radius = {5, 5};

                var region = new Cairo.Region.rectangles (rects);
                if (!region.equal (last_region)) {
                    var blur_mask = DeepinUtils.build_blur_mask (rects, radius);
                    background.set_blur_mask (blur_mask);
                    last_region = region;
                }

                popup_lighter.clear_effects ();
                popup_lighter.add_effect_with_name ( "shadow",
                        new ShadowEffect ((int)popup_lighter.width, (int)popup_lighter.height, 18, 0, 30, 3));

                popup.opacity = 255;
                visible = true;
            }
            var active_workspace = screen.get_active_workspace ();
            select_workspace (active_workspace.index (), true);
            start_timer ();
        }

        public void close ()
        {
            visible = false;
            popup.destroy_all_children ();
        }

        public void place_workspaces ()
        {
            var i = 0;
            foreach (var child in popup.get_children ()) {
                place_child (child, i);
                i++;
            }
        }

        public void select_workspace (int index, bool animate)
        {
            foreach (var child in popup.get_children ()) {
                var thumb_workspace = child as DeepinWorkspaceSnapshot;
                if (thumb_workspace.workspace.index () == index) {
                    thumb_workspace.set_select (true, animate);
                } else {
                    thumb_workspace.set_select (false, animate);
                }
            }
        }

        public void get_prefer_thumb_size (out float width, out float height)
        {
            width = monitor_geom.width * WORKSPACE_SCALE;
            height = monitor_geom.height * WORKSPACE_SCALE;
        }

        void place_child (Actor child, int index)
        {
            float child_width = 0, child_height = 0;
            float child_spacing = monitor_geom.width * SPACING_PERCENT;

            get_prefer_thumb_size (out child_width, out child_height);

            child.width = child_width;
            child.height = child_height;

            child.y = MARGIN_VERTICAL;
            child.x = (child_width + child_spacing) * index + MARGIN_HORIZONTAL;
        }

		public void relayout ()
        {
            monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

            set_position (monitor_geom.x, monitor_geom.y);
            set_size (monitor_geom.width, monitor_geom.height);

            float child_width = 0, child_height = 0;
            float child_spacing = monitor_geom.width * SPACING_PERCENT;
            get_prefer_thumb_size (out child_width, out child_height);

            var n = screen.get_n_workspaces ();
            popup.width = (child_width + child_spacing) * n + MARGIN_HORIZONTAL * 2 - child_spacing;
            popup.height = child_height + 2 * MARGIN_VERTICAL; 

            popup.set_position ((monitor_geom.width - popup.width) / 2,
                    (monitor_geom.height - popup.height) / 2);

            place_workspaces ();
        }
    }
}
