# -*- coding: utf-8 -*-
from odoo import models, fields


class TshirtProductionStage(models.Model):
    """
    Production stages for the T-shirt branding workflow.
    Drag-and-drop reorderable. Defaults loaded from data/production_stages.xml:
        Art Work → Proofing → Frame Making → Printing → QC → Done
    """
    _name = 'tshirt.production.stage'
    _description = 'T-Shirt Production Stage'
    _order = 'sequence, id'

    name = fields.Char(string='Stage Name', required=True, translate=True)
    sequence = fields.Integer(default=10)
    fold = fields.Boolean(string='Folded in Kanban', default=False)
    is_done = fields.Boolean(string='Closing Stage', default=False,
                             help='If true, orders here are considered complete')
    color = fields.Integer(string='Color')
    description = fields.Text(translate=True)

    # SLA — alert if order stuck > X hours in this stage
    sla_hours = fields.Integer(string='SLA (hours)', default=24,
                               help='Alert if an order remains in this stage longer than this')
