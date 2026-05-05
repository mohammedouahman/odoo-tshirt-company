# -*- coding: utf-8 -*-
from odoo import models, fields, api
from odoo.exceptions import UserError


class TshirtProductionOrder(models.Model):
    """
    A production order represents one branded T-shirt job moving through
    the stages: Art Work → Proofing → Frame Making → Printing → QC → Done.

    Created automatically from a confirmed Sales Order line that contains
    customizable products.
    """
    _name = 'tshirt.production.order'
    _description = 'T-Shirt Production Order'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'priority desc, deadline asc, id desc'
    _rec_name = 'reference'

    # --- Identification ---
    reference = fields.Char(string='Reference', required=True, copy=False,
                            default=lambda self: self.env['ir.sequence'].next_by_code('tshirt.production') or 'NEW',
                            tracking=True)
    sale_order_id = fields.Many2one('sale.order', string='Source Sales Order',
                                    required=True, ondelete='cascade', tracking=True)
    sale_line_id = fields.Many2one('sale.order.line', string='Order Line')
    partner_id = fields.Many2one(related='sale_order_id.partner_id', store=True, readonly=True)

    # --- Workflow ---
    stage_id = fields.Many2one('tshirt.production.stage', string='Stage',
                               group_expand='_read_group_stage_ids',
                               default=lambda self: self.env['tshirt.production.stage'].search([], limit=1),
                               tracking=True, ondelete='restrict')
    is_done = fields.Boolean(related='stage_id.is_done', store=True)

    priority = fields.Selection([
        ('0', 'Normal'),
        ('1', 'High'),
        ('2', 'Urgent'),
    ], default='0', tracking=True)

    # --- Schedule ---
    deadline = fields.Date(string='Deadline', tracking=True)
    started_at = fields.Datetime(string='Started At', readonly=True)
    completed_at = fields.Datetime(string='Completed At', readonly=True)

    # --- Custom branding details (the Excel-replacement fields) ---
    logo_file = fields.Binary(string='Logo / Artwork', attachment=True)
    logo_filename = fields.Char(string='Logo Filename')
    placement_notes = fields.Text(string='Placement Instructions',
                                  help='Where on the shirt? Front-center? Back? Sleeve?')
    color_specs = fields.Text(string='Color Specifications',
                              help='Pantone codes, ink type, etc.')
    quantity = fields.Integer(string='Quantity', default=1)
    requires_new_frame = fields.Boolean(string='New Frame Needed',
                                        help='Tick if the design requires manufacturing a new screen-printing frame')

    # --- Time tracking (the founder's "efficiency analytics" requirement) ---
    timesheet_ids = fields.One2many('account.analytic.line', 'tshirt_production_id',
                                    string='Time Entries')
    total_hours = fields.Float(string='Total Hours', compute='_compute_total_hours', store=True)

    # --- Dashboard helpers ---
    color = fields.Integer(related='stage_id.color', store=True)
    stage_age_hours = fields.Float(string='Hours in Stage', compute='_compute_stage_age')
    is_late = fields.Boolean(string='Late', compute='_compute_is_late', search='_search_is_late')

    # ========================================================================
    # Computed methods
    # ========================================================================
    @api.depends('timesheet_ids.unit_amount')
    def _compute_total_hours(self):
        for rec in self:
            rec.total_hours = sum(rec.timesheet_ids.mapped('unit_amount'))

    def _compute_stage_age(self):
        now = fields.Datetime.now()
        for rec in self:
            last_change = rec.write_date or rec.create_date
            rec.stage_age_hours = (now - last_change).total_seconds() / 3600 if last_change else 0.0

    def _compute_is_late(self):
        for rec in self:
            sla = rec.stage_id.sla_hours or 0
            rec.is_late = sla and rec.stage_age_hours > sla and not rec.is_done

    def _search_is_late(self, operator, value):
        # Simplified — fetch and filter in python
        records = self.search([('is_done', '=', False)])
        late_ids = records.filtered(lambda r: r.is_late).ids
        if (operator == '=' and value) or (operator == '!=' and not value):
            return [('id', 'in', late_ids)]
        return [('id', 'not in', late_ids)]

    # ========================================================================
    # Stage helpers
    # ========================================================================
    @api.model
    def _read_group_stage_ids(self, stages, domain, order=None):
        """Show all stages in Kanban even if no records in them."""
        return stages.search([], order=order or 'sequence, id')

    def write(self, vals):
        if 'stage_id' in vals:
            new_stage = self.env['tshirt.production.stage'].browse(vals['stage_id'])
            for rec in self:
                if not rec.started_at:
                    vals['started_at'] = fields.Datetime.now()
                if new_stage.is_done and not rec.completed_at:
                    vals['completed_at'] = fields.Datetime.now()
        return super().write(vals)

    # ========================================================================
    # Actions
    # ========================================================================
    def action_view_sale_order(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'res_model': 'sale.order',
            'view_mode': 'form',
            'res_id': self.sale_order_id.id,
        }

    def action_log_time(self):
        """Open a timesheet entry pre-filled for this production order."""
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'res_model': 'account.analytic.line',
            'view_mode': 'form',
            'context': {
                'default_tshirt_production_id': self.id,
                'default_name': f'Work on {self.reference}',
            },
            'target': 'new',
        }


class AccountAnalyticLine(models.Model):
    """Link timesheet entries to production orders for time-per-stage analytics."""
    _inherit = 'account.analytic.line'

    tshirt_production_id = fields.Many2one('tshirt.production.order',
                                           string='T-Shirt Production',
                                           ondelete='cascade')
    tshirt_stage_id = fields.Many2one(related='tshirt_production_id.stage_id',
                                      store=True, string='Stage')
