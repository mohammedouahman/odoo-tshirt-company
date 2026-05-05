# -*- coding: utf-8 -*-
{
    'name': 'T-Shirt Branding Manager',
    'version': '18.0.1.0.0',
    'category': 'Manufacturing',
    'summary': 'Custom workflow for T-shirt branding: lead → proof → frame → print → ship',
    'description': """
T-Shirt Branding Company — End-to-End Workflow
================================================

Solves the "Excel mess" pain point with:

* Custom production stages: Art Work → Proofing → Frame Making → Printing → QC → Done
* Logo / artwork upload directly on Sales Orders (B2B & B2C)
* Lead scoring & prioritization for the sales team
* Time tracking per production stage (employee efficiency analytics)
* Unified product catalog (B2B + B2C in one DB)
* Custom Kanban dashboards for shop-floor visibility

Designed for a 15-employee company doing ~30 B2B orders/day + B2C web store.
    """,
    'author': 'T-Shirt Co. / Built with Claude',
    'website': 'https://example.com',
    'license': 'LGPL-3',

    'depends': [
        'base',
        'mail',
        'sale_management',
        'crm',
        'mrp',
        'website_sale',
        'hr_timesheet',
        'account',
        'stock',
    ],

    'data': [
        # Security
        'security/security_groups.xml',
        'security/ir.model.access.csv',

        # Data
        'data/production_stages.xml',
        'data/lead_scoring_rules.xml',
        'data/mail_templates.xml',

        # Views
        'views/menus.xml',
        'views/sale_order_views.xml',
        'views/crm_lead_views.xml',
        'views/production_order_views.xml',
        'views/dashboard_views.xml',
    ],

    'assets': {
        'web.assets_backend': [
            'tshirt_branding/static/src/css/dashboard.css',
        ],
    },

    'installable': True,
    'application': True,
    'auto_install': False,
}
