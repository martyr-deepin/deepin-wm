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
	 * Customized layout for DeepinWindowSwitcher.
	 */
	public class DeepinWindowSwitcherLayout : LayoutManager
	{
		const int COLUMN_SPACING = 20;
		const int ROW_SPACING = 20;
		const int MIN_ITEMS_EACH_ROW = 7;
		const int MAX_ROWS = 2;

		float _max_width = 1024.0f;
		public float max_width
		{
			get {return _max_width;}
			set {
				_max_width = value;
				layout_changed ();
			}
		}

		public DeepinWindowSwitcherLayout ()
		{
			Object ();
		}

		public override void get_preferred_width (Clutter.Container container, float for_height,
												  out float min_width_p, out float nat_width_p)
		{
			float box_width, box_height, item_width, item_height;
			int max_items_each_row;
			do_get_preferred_size (container, out box_width, out box_height, out item_width,
								   out item_height, out max_items_each_row);
			nat_width_p = box_width;
			min_width_p = box_width;
		}

		public override void get_preferred_height (Clutter.Container container, float for_width,
												   out float min_height_p, out float nat_height_p)
		{
			float box_width, box_height, item_width, item_height;
			int max_items_each_row;
			do_get_preferred_size (container, out box_width, out box_height, out item_width,
								   out item_height, out max_items_each_row);
			nat_height_p = box_height;
			min_height_p = box_height;
		}

		void do_get_preferred_size (Clutter.Container container, out float box_width,
									out float box_height, out float item_width,
									out float item_height, out int max_items_each_row)
		{
			var actor = container as Actor;

			bool item_need_scale = false;
			item_width = DeepinWindowSwitcherItem.PREFER_WIDTH;
			item_height = DeepinWindowSwitcherItem.PREFER_HEIGHT;

			// Calculate maximize item numuber in each row. Firstly, each row must could own at
			// least 7 items, if the screen width is limitation, just decrease the size of
			// item. Secondly, limite the row numbers.
			max_items_each_row = (int)((_max_width + COLUMN_SPACING) /
									   (DeepinWindowSwitcherItem.PREFER_WIDTH + COLUMN_SPACING));
			if (max_items_each_row < MIN_ITEMS_EACH_ROW &&
				actor.get_n_children () > max_items_each_row) {
				item_need_scale = true;
				if (actor.get_n_children () < MIN_ITEMS_EACH_ROW) {
					max_items_each_row = actor.get_n_children ();
				} else {
					max_items_each_row = MIN_ITEMS_EACH_ROW;
				}
			}
			if (max_items_each_row * MAX_ROWS < actor.get_n_children ()) {
				max_items_each_row = (int)Math.ceil ((float)actor.get_n_children () / MAX_ROWS);
				item_need_scale = true;
			}

			if (item_need_scale) {
				item_width = (_max_width + COLUMN_SPACING) / max_items_each_row - COLUMN_SPACING;
				float item_scale = item_width / DeepinWindowSwitcherItem.PREFER_WIDTH;
				item_height = DeepinWindowSwitcherItem.PREFER_HEIGHT * item_scale;
			}

			if (actor.get_n_children () < max_items_each_row) {
				if (actor.get_n_children () > 0) {
					box_width =
						(item_width + COLUMN_SPACING) * actor.get_n_children () - COLUMN_SPACING;
				} else {
					box_width = 0;
				}
			} else {
				box_width = (item_width + COLUMN_SPACING) * max_items_each_row - COLUMN_SPACING;
			}

			int rows = (int)Math.ceil ((float)actor.get_n_children () / max_items_each_row);
			if (rows > 0) {
				box_height = (item_height + ROW_SPACING) * rows - ROW_SPACING;
			} else {
				box_height = 0;
			}
		}

		/**
		 * Place items in one row if their prefer size could be put down, or the items will be wrap
		 * to 2 lines. If still can not be put down, just descrease the item's size. At the same
		 * time, each row must own at least 7 items, or descrease the item's size again.
		 */
		public override void allocate (Clutter.Container container, Clutter.ActorBox box,
									   Clutter.AllocationFlags flags)
		{
			float box_width, box_height, item_width, item_height;
			int max_items_each_row;
			do_get_preferred_size (container, out box_width, out box_height, out item_width,
								   out item_height, out max_items_each_row);

			var actor = container as Actor;
			for (int i = 0; i < actor.get_n_children (); i++) {
				unowned Actor child = actor.get_child_at_index (i);
				int index_row = i / max_items_each_row;
				int index_column = i - max_items_each_row * index_row;
				int child_x = (int)((item_width + COLUMN_SPACING) * index_column);
				int child_y = (int)((item_height + ROW_SPACING) * index_row);

				var child_box = ActorBox ();
				child_box.set_size (item_width, item_height);
				child_box.set_origin (child_x, child_y);
				child.allocate (child_box, flags);
			}
		}
	}
}
