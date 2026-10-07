from argparse import ArgumentParser
from datetime import date
from pathlib import Path

import pystac
from lightning2ec.earthcare_io import query_catalogue


parser = ArgumentParser(description="Save EarthCARE MSI/CPR STAC metadata with HTTPS product assets.")
parser.add_argument('--start-date', type=date.fromisoformat)
parser.add_argument('--end-date', type=date.fromisoformat)
parser.add_argument('--item-id', action='append', default=[])
parser.add_argument('--frame', action='append')
parser.add_argument('--output-dir', type=Path, default=Path('cwl/earthcare'))
args = parser.parse_args()
if bool(args.start_date) != bool(args.end_date) or (not args.item_id and not args.start_date):
    parser.error('Supply --item-id or both --start-date and --end-date.')

items = query_catalogue(['MSI_COP_2A', 'CPR_FMR_2A'], args.frame or ['A', 'B', 'D', 'E', 'F', 'H'],
                        args.start_date, args.end_date, item_ids=args.item_id)
if not items:
    parser.error('No EarthCARE Items found for this search.')
catalog = pystac.Catalog('earthcare-inputs', description='EarthCARE MSI and CPR input products.')
catalog.add_items(items)
catalog.normalize_and_save(str(args.output_dir.resolve()), catalog_type=pystac.CatalogType.SELF_CONTAINED)
