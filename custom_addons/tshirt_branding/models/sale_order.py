# -*- coding: utf-8 -*-
from odoo import models, fields, api


class SaleOrder(models.Model):
    """Extend Sales Order with T-shirt branding fields + auto-create production orders."""
    _inherit = 'sale.order'

    # --- B2B / B2C tagging ---
    is_b2b = fields.Boolean(string='B2B Order', compute='_compute_is_b2b', store=True,
                            help='Auto-detected from customer type')

    # --- Branding details (uploaded by customer or sales rep) ---
    branding_logo = fields.Binary(string='Customer Logo / Artwork', attachment=True)
    branding_logo_filename = fields.Char(string='Logo Filename')
    branding_placement = fields.Selection([
        ('front_center', 'Front - Center'),
        ('front_left', 'Front - Left Chest'),
        ('back_center', 'Back - Center'),
        ('back_top', 'Back - Top'),
        ('sleeve_left', 'Left Sleeve'),
        ('sleeve_right', 'Right Sleeve'),
        ('custom', 'Custom (see notes)'),
    ], string='Logo Placement', default='front_center')
    branding_color_specs = fields.Text(string='Color Specs (Pantone, etc.)')
    branding_special_notes = fields.Text(string='Special Instructions')
    requires_new_frame = fields.Boolean(string='New Print Frame Needed', default=False)
    requires_artwork = fields.Boolean(string='Artwork Design Needed', default=False)

    # --- Linked production orders ---
    production_order_ids = fields.One2many('tshirt.production.order', 'sale_order_id',
                                           string='Production Orders')
    production_count = fields.Integer(compute='_compute_production_count')

    @api.depends('partner_id', 'partner_id.is_company')
    def _compute_is_b2b(self):
        for order in self:
            order.is_b2b = bool(order.partner_id.is_company)

    @api.depends('production_order_ids')
    def _compute_production_count(self):
        for order in self:
            order.production_count = len(order.production_order_ids)

    def action_confirm(self):
        """On confirmation: create a production order for each branded product line."""
        result = super().action_confirm()
        Stage = self.env['tshirt.production.stage']
        Production = self.env['tshirt.production.order']

        # Determine starting stage: artwork if needed, else proofing/frame
        for order in self:
            if not order.branding_logo and not order.requires_artwork and not order.requires_new_frame:
                continue   # not a branded order — skip

            start_stage = (
                Stage.search([('name', 'ilike', 'Art Work')], limit=1)
                if order.requires_artwork else
                Stage.search([('name', 'ilike', 'Frame')], limit=1)
                if order.requires_new_frame else
                Stage.search([('name', 'ilike', 'Proof')], limit=1)
            ) or Stage.search([], limit=1)

            for line in order.order_line.filtered(lambda l: l.product_id.type in ('consu', 'product')):
                Production.create({
                    'sale_order_id': order.id,
                    'sale_line_id': line.id,
                    'stage_id': start_stage.id,
                    'logo_file': order.branding_logo,
                    'logo_filename': order.branding_logo_filename,
                    'placement_notes': dict(self._fields['branding_placement'].selection).get(
                        order.branding_placement, ''
                    ) + ('\n' + (order.branding_special_notes or '') if order.branding_special_notes else ''),
                    'color_specs': order.branding_color_specs,
                    'quantity': int(line.product_uom_qty),
                    'requires_new_frame': order.requires_new_frame,
                    'deadline': order.commitment_date and order.commitment_date.date(),
                })
        return result

    def action_view_production_orders(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': 'Production Orders',
            'res_model': 'tshirt.production.order',
            'view_mode': 'kanban,list,form',
            'domain': [('sale_order_id', '=', self.id)],
            'context': {'default_sale_order_id': self.id},
        }
