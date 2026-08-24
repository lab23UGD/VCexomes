"""VCexomes QC | coverage plots.

Builds cumulative coverage curves from the per-sample coverage tables produced
in step 03, optionally colouring the samples by a metadata column (sequencing
pool, library, centre) taken from the pool distribution file.

Usage:
    python qc/coverage_plots.py \
        --input ./ --output ./plots \
        --coverage all_probes.csv \
        --db Distribucion_pooles_20240220.txt \
        --is-probe --group-by pool12 --outname fisdm4_probes

Inputs:
    --coverage  CSV with three columns and no header: sample, coverage, bases.
    --db        TSV with the per-sample metadata, no header. The column names
                are given by --db-columns.

Output:
    One PNG per run in the output folder.

Creation date: 2023-10-06
Author: Celeste Moya-Valera (cmoya@incliva.es)
"""

import argparse
import sys

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
import seaborn as sns  # noqa: E402
from scipy.interpolate import make_interp_spline  # noqa: E402

DEFAULT_DB_COLUMNS = [
    "sample",
    "gatk_processed_mean_coverage",
    "gatk_processed_median_coverage",
    "library",
]

COVERAGE_MARKS = (10, 20, 50)


def parse_arguments():
    """Return the parsed command-line arguments."""
    parser = argparse.ArgumentParser(description="Coverage representation for VCexomes")

    parser.add_argument("--input", required=True, help="Input folder with the coverage files")
    parser.add_argument("--output", required=True, help="Output folder for the plots")
    parser.add_argument("--coverage", required=True, help="CSV file with sample, coverage and bases")
    parser.add_argument("--db", required=True, help="TSV file with the per-sample metadata")
    parser.add_argument(
        "--db-columns",
        nargs="+",
        default=DEFAULT_DB_COLUMNS,
        help="Column names of the metadata file, in order (default: %(default)s)",
    )

    panel = parser.add_mutually_exclusive_group()
    panel.add_argument("--is-probe", action="store_true", help="The coverage file refers to probes")
    panel.add_argument("--is-target", action="store_true", help="The coverage file refers to targets")

    parser.add_argument("--title", default="", help="Extra text appended to the plot title")
    parser.add_argument("--outname", default="output", help="Base name of the output PNG")
    parser.add_argument(
        "--group-by",
        default="all",
        help="Metadata column used to colour the samples, or 'all' for one colour per sample",
    )
    parser.add_argument(
        "--low-coverage-threshold",
        type=int,
        default=5,
        help="Coverage level reported in the low-coverage summary (default: %(default)s)",
    )

    return parser.parse_args()


def load_data(args):
    """Read the coverage and metadata files and return the merged table."""
    metadata = pd.read_csv(
        f"{args.input}/{args.db}", sep="\t", names=args.db_columns, header=None
    )

    coverage = pd.read_csv(
        f"{args.input}/{args.coverage}",
        sep=",",
        names=["sample", "coverage", "bases"],
        header=None,
    )
    coverage["percentage_bases"] = coverage["bases"] * 100
    coverage["sample"] = coverage["sample"].str.split("_").str[0].astype("int64")

    return pd.merge(coverage, metadata, on="sample", how="left")


def report_low_coverage(data, threshold):
    """Print the samples whose base percentage falls below the threshold."""
    low = data[(data["coverage"] == threshold) & (data["percentage_bases"] < threshold)]
    samples = sorted(low["sample"].unique())
    print(f"Samples with low coverage at {threshold}x: {len(samples)}")
    if samples:
        print(" ".join(str(sample) for sample in samples))


def smooth_curve(x_values, y_values, points=300):
    """Interpolate a curve with a cubic spline for display purposes."""
    x_new = np.linspace(x_values.min(), x_values.max(), points)
    spline = make_interp_spline(x_values, y_values, k=3)
    return x_new, spline(x_new)


def panel_label(args):
    """Return the plot title for the panel type given on the command line."""
    if args.is_probe:
        return f"Probes {args.title}".strip()
    if args.is_target:
        return f"Targets {args.title}".strip()
    return args.title.strip() or "Coverage"


def plot_coverage(data, args, group_column=None):
    """Plot one cumulative coverage curve per sample.

    When group_column is given, samples sharing a value are drawn in the same
    colour and the legend shows one entry per group instead of per sample.
    """
    figure, axis = plt.subplots(figsize=(20, 10))

    colour_of = {}
    if group_column is not None:
        groups = data[group_column].dropna().unique()
        palette = sns.color_palette("Set1", n_colors=len(groups))
        colour_of = dict(zip(groups, palette))

    for sample_name, group in data.groupby("sample"):
        if len(group) < 4:
            print(f"Skipping sample {sample_name}: not enough points to interpolate")
            continue

        x_new, y_smooth = smooth_curve(group["coverage"], group["percentage_bases"])

        if group_column is None:
            axis.plot(x_new, y_smooth, label=sample_name, alpha=0.7)
        else:
            value = group[group_column].iloc[0]
            axis.plot(x_new, y_smooth, color=colour_of.get(value, "black"), alpha=1)

    if group_column is not None:
        handles = [
            plt.Line2D([0], [0], color=colour, label=value)
            for value, colour in colour_of.items()
        ]
        axis.legend(handles=handles, loc="center left", bbox_to_anchor=(1, 0.5))

    for mark in COVERAGE_MARKS:
        axis.axvline(x=mark, color="red", linestyle="--", alpha=0.4)

    axis.set_xlabel("Coverage")
    axis.set_ylabel("Base percentage")
    axis.set_title(panel_label(args))

    suffix = group_column if group_column is not None else "all_samples"
    output_path = f"{args.output}/{args.outname}_{suffix}.png"
    figure.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(figure)
    print(f"Plot written to {output_path}")


def main():
    args = parse_arguments()
    data = load_data(args)
    report_low_coverage(data, args.low_coverage_threshold)

    group_column = None
    if args.group_by != "all":
        if args.group_by not in data.columns:
            available = ", ".join(column for column in data.columns if column != "sample")
            sys.exit(
                f"ERROR: column '{args.group_by}' is not present in the metadata. "
                f"Available columns: {available}"
            )
        group_column = args.group_by

    plot_coverage(data, args, group_column)


if __name__ == "__main__":
    main()
