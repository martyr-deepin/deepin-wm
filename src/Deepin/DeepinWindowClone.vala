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
	 * A container for a clone of the texture of a MetaWindow, a WindowIcon, a close button and a
	 * shadow. Used together with the WindowCloneContainer.
	 */
	public class DeepinWindowClone : Actor
	{
		public const AnimationMode LAYOUT_MODE = AnimationMode.EASE_OUT_QUAD;
        public const uint8 SHADOW_OPACITY = 50;

		const int FADE_IN_DURATION = 500;
		const int FADE_OUT_DURATION = 300;
		const AnimationMode CLOSE_MODE = AnimationMode.EASE_IN_QUAD;

		const int ICON_SIZE = 64;

		/**
		 * The window was activated by clicking or pressing enter. The MultitaskingView should
		 * consider activating the window and closing the view.
		 */
		public signal void activated ();

		/**
		 * The window will be closed after closing animation finished.
		 */
		public signal void closing ();

		public signal void entered ();

		/**
		 * The window was moved or resized and a relayout of the tiling layout may be sensible right
		 * now.
		 */
		public signal void request_reposition ();

		public Meta.Window window { get; construct; }

		/**
		 * The currently assigned slot of the window in the tiling layout. May be null.
		 */
		public Meta.Rectangle? slot { get; private set; default = null; }

		public bool dragging { get; private set; default = false; }

		public int layout_duration { get; set; default = 400; }

		/**
		 * When selected fades a highlighted border around the window in. Used for the visually
		 * indicating the WindowCloneContainer's current_window.
		 */
		bool _select = false;

		// for thumbnail mode, shadow, icon and close button will be disabed
		public bool thumbnail_mode { get; construct; }

		public bool enable_shadow = true;
		public bool enable_icon = true;
		public bool enable_buttons = true;

		DragDropAction? drag_action = null;
        ClickAction? long_press_action = null;
		Clone? clone = null;

		// shape border size could be override in css
		int shape_border_size = 5;

		Actor prev_parent = null;
		int prev_index = -1;
		uint prev_opacity = 255;
		ulong check_confirm_dialog_cb = 0;
		uint shadow_update_timeout = 0;
        ulong show_callback_id = 0UL;

		Actor shape;
		DeepinIconActor? close_button = null;
        // pin here means keep on top
		DeepinIconActor? pin_button = null;
		DeepinIconActor? unpin_button = null;
		GtkClutter.Texture? window_icon = null;

		public DeepinWindowClone (Meta.Window window, bool thumbnail_mode = false)
		{
			Object (window: window, thumbnail_mode: thumbnail_mode);
		}

		construct
		{
			if (thumbnail_mode) {
				enable_shadow = false;
				enable_icon = false;
				enable_buttons = false;
			} else {
				enable_shadow = true;
				enable_icon = true;
				enable_buttons = true;
			}

			reactive = true;
			set_pivot_point (0.5f, 0.5f);
			shape_border_size =
				DeepinUtils.get_css_border_radius ("deepin-window-clone", Gtk.StateFlags.SELECTED);

			window.unmanaged.connect (unmanaged);
			window.notify["on-all-workspaces"].connect (on_all_workspaces_changed);
			window.position_changed.connect (() => request_reposition ());

			drag_action =
				new DragDropAction (DragDropActionType.SOURCE, "deepin-multitaskingview-window");
			drag_action.drag_begin.connect (on_drag_begin);
			drag_action.drag_end.connect (on_drag_end);
			drag_action.drag_canceled.connect (on_drag_canceled);
			//drag_action.actor_clicked.connect (on_actor_clicked);
            add_action (drag_action);

            long_press_action = new Clutter.ClickAction ();
            long_press_action.long_press_duration = DeepinTouchscreenSettings.get_default ().longpress_duration;
            long_press_action.long_press_threshold = Clutter.Settings.get_default ().dnd_drag_threshold;
            long_press_action.clicked.connect(() => {
                    on_actor_clicked (long_press_action.get_button ());
                });
            long_press_action.long_press.connect((actor, state) => {
                    switch (state) {
                    case LongPressState.QUERY:
                        return true;
                    case LongPressState.ACTIVATE:
                        animate_buttons (true);
                        return true;
                    default:
                        return false;
                    }
                });
            add_action (long_press_action);

			if (enable_buttons) {
				close_button = new DeepinIconActor ("close");
				close_button.opacity = 0;
				close_button.released.connect (() => {
					close_window ();
				});
				add_child (close_button);

				pin_button = new DeepinIconActor ("unsticked");
				pin_button.opacity = 0;
				pin_button.released.connect (() => {
                    window.make_above ();
				});
				add_child (pin_button);

				unpin_button = new DeepinIconActor ("sticked");
				unpin_button.opacity = 0;
				unpin_button.released.connect (() => {
                    window.unmake_above ();
				});
				add_child (unpin_button);

                pin_button.visible = !window.is_above ();
                unpin_button.visible = window.is_above ();
                window.notify["above"].connect (on_above_state_changed);
			}

			if (enable_icon) {
                reload_icon ();
                DeepinXSettings.get_default ().schema.changed.connect (reload_icon);
			}

			shape = new DeepinCssStaticActor ("deepin-window-clone", Gtk.StateFlags.SELECTED);
			shape.opacity = 0;
			add_child (shape);

			load_clone ();
		}

        void reload_icon ()
        {
            if (window_icon != null) {
                remove_child (window_icon);
            }
            var icon_size = (int)(ICON_SIZE * DeepinXSettings.get_default ()
                    .schema.get_double ("scale-factor"));
            window_icon = new WindowIcon (window, icon_size);
            window_icon.opacity = 0;
            window_icon.set_pivot_point (0.5f, 0.5f);
            add_child (window_icon);
        }

		~DeepinWindowClone ()
		{
			window.unmanaged.disconnect (unmanaged);
			window.notify["on-all-workspaces"].disconnect (on_all_workspaces_changed);
            window.notify["above"].disconnect (on_above_state_changed);

			if (shadow_update_timeout != 0) {
				Source.remove (shadow_update_timeout);
			}

			if (enable_shadow) {
				window.size_changed.disconnect (update_shadow_size);
			}
		}

		/**
		 * Waits for the texture of a new WindowActor to be available and makes a close of it. If it
		 * was already was assigned a slot at this point it will animate to it. Otherwise it will
		 * just place itself at the location of the original window. Also adds the shadow effect and
		 * makes sure the shadow is updated on size changes.
		 *
		 * @param was_waiting Internal argument used to indicate that we had to wait before the
		 *                    window's texture became available.
		 */
		void load_clone (bool was_waiting = false)
		{
			var actor = window.get_compositor_private () as WindowActor;
			if (actor == null) {
				Idle.add (() => {
					if (window.get_compositor_private () != null) {
						load_clone (true);
					}
					return false;
				});

				return;
			}

			clone = new Clone (actor.get_texture ());
			add_child (clone);

			set_child_below_sibling (shape, clone);
			if (enable_buttons) {
				set_child_above_sibling (close_button, clone);
				set_child_above_sibling (pin_button, clone);
				set_child_above_sibling (unpin_button, clone);
			}
			if (window_icon != null) {
				set_child_above_sibling (window_icon, clone);
			}

			transition_to_original_state (false);

            show_callback_id = notify["realized"].connect(() => {
                if (!actor.is_destroyed() && enable_shadow &&
                        visible && get_effect ("shadow") == null) {
                    Meta.verbose ("lazy add shadow effect\n");
                    var outer_rect = window.get_frame_rect ();
                    add_effect_with_name (
                        "shadow", new ShadowEffect (outer_rect.width, outer_rect.height, 40, 5, SHADOW_OPACITY, -1, true, false));
                    window.size_changed.connect (update_shadow_size);
                }
                SignalHandler.disconnect (this, show_callback_id);
                show_callback_id = 0UL;
            });

			// If we were waiting the view was most probably already opened when our window finally
			// got available. So we fade-in and make sure we took the took place.  If the slot is
			// not available however, the view was probably closed while this window was opened, so
			// we stay at our old place.
			if (was_waiting && slot != null) {
				opacity = 0;
				take_slot (slot);
				opacity = 255;

				request_reposition ();
			}
		}

		/**
		 * Sets a timeout of 500ms after which, if no new resize action reset it, the shadow will be
		 * resized and a request_reposition() will be emitted to make the WindowCloneContainer
		 * calculate a new layout to honor the new size.
		 */
		void update_shadow_size ()
		{
			if (shadow_update_timeout != 0) {
				Source.remove (shadow_update_timeout);
			}

			shadow_update_timeout = Timeout.add (500, () => {
				var rect = window.get_frame_rect ();
				var shadow_effect = get_effect ("shadow") as ShadowEffect;
				if (shadow_effect != null) {
					shadow_effect.update_size (rect.width, rect.height);
				}

				shadow_update_timeout = 0;

				// if there was a size change it makes sense to recalculate the positions
				request_reposition ();

				return false;
			});
		}

        void on_above_state_changed ()
        {
            if (enable_buttons) {
                pin_button.visible = !window.is_above ();
                unpin_button.visible = window.is_above ();
            }
        }

		void on_all_workspaces_changed ()
		{
			// we don't display windows that are on all workspaces
            if (window.on_all_workspaces) {
                unmanaged ();
            }
		}

		public void set_select (bool value, bool animate = true) {
			_select = value;

			shape.save_easing_state ();

			shape.set_easing_duration (animate ? layout_duration : 0);
			shape.set_easing_mode (LAYOUT_MODE);
			shape.opacity = _select ? 255 : 0;

			shape.restore_easing_state ();
		}
		public bool is_selected () {
			return _select;
		}

		/**
		 * If we are in multitaskingview mode, we may display windows from workspaces other than the
		 * current one. To ease their appearance we have to fade them in. And if the window is
		 * minimized, it should be fade, too,
		 */
		public bool should_fade ()
		{
			return (window.get_workspace () != window.get_screen ().get_active_workspace () ||
					!window.showing_on_its_workspace ());
		}

		/**
		 * Place the window at the location of the original MetaWindow
		 *
		 * @param animate Animate the transformation of the placement
		 */
		public void transition_to_original_state (bool animate)
		{
			var outer_rect = window.get_frame_rect ();

			float offset_x = 0, offset_y = 0;

			var parent = get_parent ();
			if (parent != null) {
				parent.get_transformed_position (out offset_x, out offset_y);
			}

			if (animate) {
				var position = Point.alloc ();
				position.x = outer_rect.x - offset_x;
				position.y = outer_rect.y - offset_y;
				var position_value = GLib.Value (typeof (Point));
				position_value.set_boxed ((void*)position);

				var size = Size.alloc ();
				size.width = outer_rect.width;
				size.height = outer_rect.height;
				var size_value = GLib.Value (typeof (Size));
				size_value.set_boxed ((void*)size);

                unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
				DeepinUtils.start_animation_group (this, "window-slot",
                                                   animation_settings.multitasking_toggle_duration,
												   DeepinUtils.clutter_set_mode_ease_out_quint,
												   "position", &position_value,
												   "size", &size_value);
			} else {
				set_position (outer_rect.x - offset_x, outer_rect.y - offset_y);
				set_size (outer_rect.width, outer_rect.height);
			}

			if (window_icon != null) {
				window_icon.save_easing_state ();

				window_icon.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);
				window_icon.set_easing_duration (animate ? 300 : 0);
				window_icon.opacity = 0;

				window_icon.restore_easing_state ();
			}

            Actor[] btns = {close_button, pin_button, unpin_button};
            foreach (var btn in btns) {
                if (btn != null) {
                    btn.save_easing_state ();

                    btn.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);
                    btn.set_easing_duration (animate ? 300 : 0);
                    btn.opacity = 0;

                    btn.restore_easing_state ();
                }
            }
		}

		/**
		 * Animate the window to the given slot.
		 *
		 * @param animate Determine if need animation.
		 * @param selecting Check if is action that window clone is selecting.
		 */
		public void take_slot (Meta.Rectangle rect, bool animate = true,
							   bool selecting = false)
		{
			slot = rect;

			if (animate) {
				var position = Point.alloc ();
				position.x = rect.x;
				position.y = rect.y;
				var position_value = GLib.Value (typeof (Point));
				position_value.set_boxed ((void*)position);

				var size = Size.alloc ();
				size.width = rect.width;
				size.height = rect.height;
				var size_value = GLib.Value (typeof (Size));
				size_value.set_boxed ((void*)size);

                unowned AnimationSettings animation_settings = AnimationSettings.get_default ();
				if (!selecting) {
					DeepinUtils.start_animation_group (this, "window-slot",
                                                       animation_settings.multitasking_toggle_duration,
													   DeepinUtils.clutter_set_mode_ease_out_quint,
													   "position", &position_value,
													   "size", &size_value);
				} else {
					DeepinUtils.start_animation_group (this, "window-slot",
													   layout_duration,
													   DeepinUtils.clutter_set_mode_ease_out_quad,
													   "position", &position_value,
													   "size", &size_value);
				}
			} else {
				save_easing_state ();
				set_easing_duration (0);

				set_position (rect.x, rect.y);
				set_size (rect.width, rect.height);

				restore_easing_state ();
			}

			if (window_icon != null) {
				window_icon.save_easing_state ();

				window_icon.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);
				window_icon.set_easing_duration (animate ? 300 : 0);
				window_icon.opacity = 255;

				window_icon.restore_easing_state ();
			}
		}

		/**
		 * Except for the texture clone and the highlight all children are placed according to their
		 * given allocations. The first two are placed in a way that compensates for invisible
		 * borders of the texture.
		 */
		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			foreach (var child in get_children ()) {
				if (child != clone && child != shape) {
					child.allocate_preferred_size (flags);
				}
			}

			ActorBox shape_box = { -shape_border_size, -shape_border_size,
								   box.get_width () + shape_border_size,
								   box.get_height () + shape_border_size };
			shape.allocate (shape_box, flags);

            if (close_button != null) {
                var close_box = ActorBox ();
                close_box.set_size (close_button.width, close_button.height);
                close_box.set_origin (box.get_width () - close_box.get_width () * 0.50f,
                        -close_button.height * 0.50f);

                close_button.allocate (close_box, flags);
            }

            if (pin_button != null) {
                var pin_box = ActorBox ();
                pin_box.set_size (pin_button.width, pin_button.height);
                pin_box.set_origin (-pin_box.get_width () * 0.50f,
                        -pin_button.height * 0.50f);

                pin_button.allocate (pin_box, flags);
            }

            if (unpin_button != null) {
                var unpin_box = ActorBox ();
                unpin_box.set_size (unpin_button.width, unpin_button.height);
                unpin_box.set_origin (-unpin_box.get_width () * 0.50f,
                        -unpin_button.height * 0.50f);

                unpin_button.allocate (unpin_box, flags);
            }

			if (!dragging && window_icon != null) {
				var icon_box = ActorBox ();
				icon_box.set_size (window_icon.width, window_icon.height);
				icon_box.set_origin ((box.get_width () - icon_box.get_width ()) / 2,
									 box.get_height () - icon_box.get_height () * 0.75f);
				window_icon.allocate (icon_box, flags);
			}

			if (clone != null) {
				var actor = window.get_compositor_private () as WindowActor;
#if HAS_MUTTER314
				var input_rect = window.get_buffer_rect ();
#else
				var input_rect = window.get_input_rect ();
#endif
				var outer_rect = window.get_frame_rect ();
				var scale_factor = (float)width / outer_rect.width;

				var shadow_effect = get_effect ("shadow") as ShadowEffect;
				if (shadow_effect != null) {
					shadow_effect.scale_factor = scale_factor;
				}

				var clone_box = ActorBox ();
				clone_box.set_origin ((input_rect.x - outer_rect.x) * scale_factor,
									  (input_rect.y - outer_rect.y) * scale_factor);
				clone_box.set_size (actor.width * scale_factor, actor.height * scale_factor);

				clone.allocate (clone_box, flags);
			}
		}

		//public override bool button_press_event (Clutter.ButtonEvent event)
		//{
			//return true;
		//}

        void animate_buttons (bool show)
        {
            Actor[] btns = {close_button, pin_button, unpin_button};
            foreach (var btn in btns) {
                if (btn != null) {
                    btn.save_easing_state ();

                    btn.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);
                    btn.set_easing_duration (200);
                    btn.opacity = show ? 255 : 0;

                    btn.restore_easing_state ();
                }
            }
        }

		public override bool enter_event (Clutter.CrossingEvent event)
		{
            animate_buttons (true);
            entered ();
			return false;
		}

		public override bool leave_event (Clutter.CrossingEvent event)
		{
            animate_buttons (false);
			return false;
		}

		public void start_fade_in_animation ()
		{
			DeepinUtils.start_fade_in_back_animation (this, FADE_IN_DURATION);
		}

		public void start_fade_out_animation (DeepinUtils.PlainCallback? cb = null)
		{
			DeepinUtils.start_fade_out_animation (this, FADE_OUT_DURATION,
												  AnimationMode.EASE_OUT_QUAD, cb);
		}

		/**
		 * Send the window the delete signal and listen for new windows to be added to the window's
		 * workspace, in which case we check if the new window is a dialog of the window we were
		 * going to delete. If that's the case, we request to select our window.
		 */
		public void close_window ()
		{
			start_fade_out_animation (do_close_window);
			closing ();
		}
		void do_close_window ()
		{
			var screen = window.get_screen ();
			check_confirm_dialog_cb = screen.window_entered_monitor.connect (check_confirm_dialog);

			window.@delete (screen.get_display ().get_current_time ());
		}

		void check_confirm_dialog (int monitor, Meta.Window new_window)
		{
			if (new_window.get_transient_for () == window) {
				Idle.add (() => {
					activated ();
					return false;
				});

				SignalHandler.disconnect (window.get_screen (), check_confirm_dialog_cb);
				check_confirm_dialog_cb = 0;
			}
		}

		/**
		 * The window unmanaged by the compositor, so we need to destroy ourselves too.
		 */
		void unmanaged ()
		{
            if (show_callback_id != 0) {
                SignalHandler.disconnect (this, show_callback_id);
                show_callback_id = 0UL;
            }

			if (drag_action != null && drag_action.dragging) {
				drag_action.cancel ();
			}

			if (clone != null) {
				clone.destroy ();
			}

			if (check_confirm_dialog_cb != 0) {
				SignalHandler.disconnect (window.get_screen (), check_confirm_dialog_cb);
				check_confirm_dialog_cb = 0;
			}

			if (shadow_update_timeout != 0) {
				Source.remove (shadow_update_timeout);
				shadow_update_timeout = 0;
			}

			destroy ();
		}

		void on_actor_clicked (uint32 button)
		{
            if (long_press_action.held)
                return;

			switch (button) {
			case 1:
				activated ();
				break;
			case 2:
				close_window ();
				break;
			}
		}

		/**
		 * A drag action has been initiated on us, we reparent ourselves to the stage so we can move
		 * freely, scale ourselves to a smaller scale and request that the position we just freed is
		 * immediately filled by the WindowCloneContainer.
		 */
		Actor on_drag_begin (float click_x, float click_y)
		{
            if (long_press_action.held) {
                long_press_action.release ();
            }


			float abs_x, abs_y;

			// get abs_x and abs_y before reparent
			get_transformed_position (out abs_x, out abs_y);

			prev_parent = get_parent ();
			prev_index = prev_parent.get_children ().index (this);

			// reparent
			var stage = get_stage ();
			prev_parent.remove_child (this);
			stage.add_child (this);

			var shadow_effect = get_effect ("shadow") as ShadowEffect;
			if (shadow_effect != null) {
				shadow_effect.shadow_opacity = 0;
			}

			float thumb_ws_width, thumb_ws_height;
			DeepinWorkspaceThumbContainer.get_prefer_thumb_size(window.get_screen (),
																out thumb_ws_width,
																out thumb_ws_height);
			var scale = thumb_ws_width * 0.7f / clone.width;

			set_pivot_point ((click_x - abs_x) / clone.width,
							 (click_y - abs_y) / clone.height);

			save_easing_state ();

			set_easing_duration (200);
			set_easing_mode (AnimationMode.EASE_IN_CUBIC);
			set_scale (scale, scale);
			set_position (click_x - abs_x - clone.width / 2,
						  click_y - abs_y - clone.height / 2);
			prev_opacity = opacity;
			opacity = 255;

			restore_easing_state ();

			request_reposition ();

			save_easing_state ();
			set_easing_duration (0);
			set_position (abs_x, abs_y);

			if (window_icon != null) {
				window_icon.opacity = 0;
			}

			if (enable_buttons) {
				close_button.opacity = 0;
				pin_button.opacity = 0;
				unpin_button.opacity = 0;
			}

			if (_select) {
				shape.opacity = 0;
			}

			dragging = true;

			return this;
		}

		/**
		 * When we cross an DeepinWorkspaceThumbClone, we animate to an even smaller size and
		 * slightly less opacity and add 16ourselves as temporary window to the group. When left, we
		 * reverse those steps.
		 */
		void on_drag_destination_crossed (Actor destination, bool hovered)
		{
			DeepinWorkspaceThumbClone? workspace_thumb = destination as DeepinWorkspaceThumbClone;
			WorkspaceInsertThumb? insert_thumb = destination as WorkspaceInsertThumb;

			// if we have don't dynamic workspace, we don't allow inserting
			if (workspace_thumb == null && insert_thumb == null ||
				(insert_thumb != null && !Prefs.get_dynamic_workspaces ())) {
				return;
			}

			// for an workspace thumbnail, we only do animations if there is an actual movement
			// possible
			if (workspace_thumb != null && workspace_thumb.workspace == window.get_workspace ()) {
				return;
			}

			var opacity = hovered ? 0 : 255;
			var duration =
				hovered && insert_thumb != null ? WorkspaceInsertThumb.EXPAND_DELAY : 100;

			clone.save_easing_state ();

			clone.set_easing_mode (AnimationMode.LINEAR);
			clone.set_easing_duration (duration);
			clone.set_opacity (opacity);

			clone.restore_easing_state ();

			if (insert_thumb != null) {
				insert_thumb.set_window_thumb (window);
			}

			if (workspace_thumb != null) {
				if (hovered) {
					workspace_thumb.window_container.add_window (window);
				} else {
					workspace_thumb.window_container.remove_window (window);
				}
			}
		}

		/**
		 * Depending on the destination we have different ways to find the correct destination.
		 * After we found one we destroy ourselves so the dragged clone immediately disappears,
		 * otherwise we cancel the drag and animate back to our old place.
		 */
		void on_drag_end (Actor destination)
		{
			Meta.Workspace workspace = null;
			var primary = window.get_screen ().get_primary_monitor ();

			if (destination is DeepinWorkspaceThumbClone) {
				workspace = ((DeepinWorkspaceThumbClone)destination).workspace;
			} else if (destination is DeepinFramedBackground) {
				workspace = ((DeepinWorkspaceFlowClone)destination.get_parent ()).workspace;
			} else if (destination is DeepinWorkspaceAdder) {
                if (Prefs.get_num_workspaces () >= WindowManagerGala.MAX_WORKSPACE_NUM) {
                    return;
                }
				window.change_workspace_by_index (Prefs.get_num_workspaces () + 1, true);
                unmanaged ();
				return;

			} else if (destination is WorkspaceInsertThumb) {
				if (!Prefs.get_dynamic_workspaces ()) {
					on_drag_canceled ();
					return;
				}

				unowned WorkspaceInsertThumb inserter = (WorkspaceInsertThumb)destination;

				var will_move = window.get_workspace ().index () != inserter.workspace_index;

				if (Prefs.get_workspaces_only_on_primary () && window.get_monitor () != primary) {
					window.move_to_monitor (primary);
					will_move = true;
				}

				InternalUtils.insert_workspace_with_window (inserter.workspace_index, window);

				// if we don't actually change workspaces, the window-added/removed signals won't be
				// emitted so we can just keep our window here
				if (!will_move) {
					on_drag_canceled ();
				} else {
					unmanaged ();
				}

				return;
			} else if (destination is MonitorClone) {
				var monitor = ((MonitorClone)destination).monitor;
				if (window.get_monitor () != monitor) {
					window.move_to_monitor (monitor);
					unmanaged ();
				} else {
					on_drag_canceled ();
				}

				return;
			}

			bool did_move = false;

			if (Prefs.get_workspaces_only_on_primary () && window.get_monitor () != primary) {
				window.move_to_monitor (primary);
				did_move = true;
			}

			if (workspace != null && workspace != window.get_workspace ()) {
				window.change_workspace (workspace);
				did_move = true;
			}

			if (did_move) {
				unmanaged ();
			} else {
				// if we're dropped at the place where we came from interpret as cancel
				on_drag_canceled ();
			}
		}

		/**
		 * Animate back to our previous position with a bouncing animation.
		 */
		void on_drag_canceled ()
		{
			get_parent ().remove_child (this);
			prev_parent.insert_child_at_index (this, prev_index);

			save_easing_state ();

			set_easing_duration (250);
			set_easing_mode (AnimationMode.EASE_OUT_QUAD);
			set_scale (1, 1);
			opacity = prev_opacity;
			rotation_angle_z = 0.0;

			restore_easing_state ();

			Clutter.Callback finished = () => {
				var shadow_effect = get_effect ("shadow") as ShadowEffect;
				if (shadow_effect != null) {
					shadow_effect.shadow_opacity = SHADOW_OPACITY;
				}
				if (_select) {
					shape.opacity = 255;
				}
			};

			var transition = clone.get_transition ("scale-x");
			if (transition != null) {
				transition.completed.connect (() => finished (this));
			} else {
				finished (this);
			}

			request_reposition ();

			// pop 0 animation duration from on_drag_begin()
			restore_easing_state ();

			if (window_icon != null) {
				window_icon.save_easing_state ();

				window_icon.set_easing_duration (250);
				window_icon.set_easing_mode (AnimationMode.EASE_OUT_QUAD);
				window_icon.set_position (
					(slot.width - window_icon.width) / 2, slot.height - window_icon.height * 0.75f);

				window_icon.restore_easing_state ();
			}

			dragging = false;
		}
	}
}
