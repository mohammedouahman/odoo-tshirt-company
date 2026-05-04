# -*- coding: utf-8 -*-
from odoo import models, fields, api


class CrmLead(models.Model):
    """
    Extend CRM Lead with a custom scoring system tailored for the T-shirt business:
      - Company size weight
      - Estimated order volume weight
      - B2B vs B2C weight
      - Source weight (web form > cold outreach)
    Sales team uses 'tshirt_priority_score' to know who to call FIRST.
    """
    _inherit = 'crm.lead'

    # --- Custom intake fields from website form ---
    estimated_quantity = fields.Integer(string='Estimated T-Shirt Quantity',
                                        help='How many shirts are they asking about?')
    needs_branding = fields.Boolean(string='Needs Custom Branding', default=True)
    desired_delivery_days = fields.Integer(string='Desired Delivery (days)')
    company_size_band = fields.Selection([
        ('xs', '1-10 employees'),
        ('s', '11-50 employees'),
        ('m', '51-200 employees'),
        ('l', '200+ employees'),
    ], string='Company Size')

    # --- Computed score ---
    tshirt_priority_score = fields.Integer(
        string='Priority Score',
        compute='_compute_tshirt_priority_score',
        store=True,
        help='0-100. Higher = call first.',
    )
    tshirt_priority_label = fields.Selection([
        ('hot', '🔥 Hot — Call Now'),
        ('warm', '☀ Warm — This Week'),
        ('cool', '❄ Cool — Nurture'),
    ], compute='_compute_tshirt_priority_score', store=True)

    @api.depends('estimated_quantity', 'company_size_band', 'source_id',
                 'medium_id', 'desired_delivery_days', 'partner_id.is_company',
                 'expected_revenue')
    def _compute_tshirt_priority_score(self):
        size_weight = {'xs': 5, 's': 15, 'm': 30, 'l': 40}
        for lead in self:
            score = 0

            # Quantity (max 30 pts)
            qty = lead.estimated_quantity or 0
            if qty >= 500:
                score += 30
            elif qty >= 100:
                score += 20
            elif qty >= 30:
                score += 10
            elif qty > 0:
                score += 5

            # Company size (max 40 pts)
            score += size_weight.get(lead.company_size_band, 0)

            # B2B premium (10 pts)
            if lead.partner_id and lead.partner_id.is_company:
                score += 10

            # Urgency (10 pts) — short timeline = high commitment
            if lead.desired_delivery_days and lead.desired_delivery_days <= 14:
                score += 10
            elif lead.desired_delivery_days and lead.desired_delivery_days <= 30:
                score += 5

            # Source (max 10 pts) — website form > paid ads > cold
            if lead.source_id and lead.source_id.name and 'website' in lead.source_id.name.lower():
                score += 10
            elif lead.medium_id and lead.medium_id.name and 'email' in lead.medium_id.name.lower():
                score += 5

            score = min(score, 100)
            lead.tshirt_priority_score = score
            lead.tshirt_priority_label = (
                'hot' if score >= 70 else
                'warm' if score >= 40 else
                'cool'
            )
