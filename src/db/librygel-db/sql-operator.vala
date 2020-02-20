/*
 * Copyright (C) 2010 Jens Georg <mail@jensge.org>.
 *
 * Author: Jens Georg <mail@jensge.org>
 *
 * This file is part of Rygel.
 *
 * Rygel is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * Rygel is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

using GUPnP;

public class Rygel.Database.SqlOperator : GLib.Object {
    protected string name;
    protected string arg;
    protected string collate;

    public SqlOperator (string name,
                        string arg,
                        string collate = "") {
        this.name = name;
        this.arg = arg;
        this.collate = collate;
    }

    public SqlOperator.from_search_criteria_op (SearchCriteriaOp op,
                                                string           arg,
                                                string           collate) {
        string sql = null;
        switch (op) {
            case SearchCriteriaOp.EQ:
                sql = "=";
                break;
            case SearchCriteriaOp.NEQ:
                sql = "!=";
                break;
            case SearchCriteriaOp.LESS:
                sql = "<";
                break;
            case SearchCriteriaOp.LEQ:
                sql = "<=";
                break;
            case SearchCriteriaOp.GREATER:
                sql = ">";
                break;
            case SearchCriteriaOp.GEQ:
                sql = ">=";
                break;
            default:
                assert_not_reached ();
        }

        this (sql, arg, collate);
    }

    public virtual string to_string () {
        return "(%s %s ? %s)".printf (arg, name, collate);
    }
}
