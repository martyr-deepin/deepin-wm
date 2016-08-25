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
        const int THUMB_SHAPE_PADDING = 2;

        public Workspace workspace { get; construct; }

        public DeepinWindowSnapshotContainer window_container;

        // selected shape for workspace thumbnail clone
        Actor thumb_shape;

        Actor workspace_shadow;
        Actor workspace_clone;

        public Actor background;

        // The DeepinRoundRectEffect works bad, so we drawing the outline to make it looks
        // antialise, but the drawing color is different for normal and selected state, so we must
        // update it manually.
        Gdk.RGBA roundRectColorNormal;
        Gdk.RGBA roundRectColorSelected;
        DeepinRoundRectOutlineEffect roundRectOutlineEffect;

        public DeepinWorkspaceSnapshot (Workspace workspace)
        {
            Object (workspace: workspace);
        }

        construct
        {
            // workspace shadow effect, angle:90°, size:5, distance:1, opacity:30%
            workspace_shadow = new Actor ();
            workspace_shadow.add_effect_with_name (
                    "shadow", new ShadowEffect (get_thumb_workspace_prefer_width (),
                        get_thumb_workspace_prefer_heigth (), 10, 1, 76));
            add_child (workspace_shadow);

            workspace.get_screen ().monitors_changed.connect (update_workspace_shadow);

            // selected shape for workspace thumbnail clone
            thumb_shape =
                new DeepinCssStaticActor ("deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
            thumb_shape.opacity = 0;
            add_child (thumb_shape);

            // workspace thumbnail clone
            workspace_clone = new Actor ();
            workspace_clone.set_pivot_point (0.5f, 0.5f);

            // setup rounded rectangle effect
            int radius = DeepinUtils.get_css_border_radius (
                    "deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
            roundRectColorNormal = DeepinUtils.get_css_background_color_gdk_rgba (
                    "deepin-window-manager");
            roundRectColorSelected = DeepinUtils.get_css_background_color_gdk_rgba (
                    "deepin-workspace-thumb-clone", Gtk.StateFlags.SELECTED);
            roundRectOutlineEffect =
                new DeepinRoundRectOutlineEffect ((int)width, (int)height, radius,
                        roundRectColorNormal);
            workspace_clone.add_effect (roundRectOutlineEffect);
            workspace_clone.add_effect (new DeepinRoundRectEffect (radius));

            background = new DeepinFramedBackground (workspace.get_screen (), workspace.index (), false);
            workspace_clone.add_child (background);

            window_container = new DeepinWindowSnapshotContainer (workspace);
            workspace_clone.add_child (window_container);


            add_child (workspace_clone);
        }

        ~DeepinWorkspaceSnapshot ()
        {
            workspace.get_screen ().monitors_changed.disconnect (update_workspace_shadow);
            background.destroy ();
        }

        public void set_select (bool value, bool animate = true)
        {
            int duration = animate ? DeepinMultitaskingView.WORKSPACE_SWITCH_DURATION : 0;

            // selected shape for workspace thumbnail clone
            thumb_shape.save_easing_state ();

            thumb_shape.set_easing_duration (duration);
            thumb_shape.set_easing_mode (AnimationMode.LINEAR);
            thumb_shape.opacity = value ? 255 : 0;

            thumb_shape.restore_easing_state ();

            // update the outline fixing color for rounded rectangle effect
            if (value) {
                roundRectOutlineEffect.update_color (roundRectColorSelected);
            } else {
                roundRectOutlineEffect.update_color (roundRectColorNormal);
            }
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

            // scale background
            float scale =
                box.get_width () != 0 ? box.get_width () / (float)monitor_geom.width : 0.5f;
            background.set_scale (scale, scale);

            var thumb_shape_box = ActorBox ();
            thumb_shape_box.set_size (
                    thumb_width + THUMB_SHAPE_PADDING * 2, thumb_height + THUMB_SHAPE_PADDING * 2);
            thumb_shape_box.set_origin (
                    (box.get_width () - thumb_shape_box.get_width ()) / 2, -THUMB_SHAPE_PADDING);
            thumb_shape.allocate (thumb_shape_box, flags);
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

        const int POPUP_TIMEOUT = 2000;

		public WindowManager wm { get; construct; }
        public Screen screen { get; construct; }

		Actor popup;
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

			popup = new DeepinCssStaticActor ("deepin-window-switcher");
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

        public void open ()
        {
            if (!visible) {
                foreach (var workspace in screen.get_workspaces ()) {
                    var snapshot = new DeepinWorkspaceSnapshot (workspace);
                    popup.add_child (snapshot);
                }
                relayout ();

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
