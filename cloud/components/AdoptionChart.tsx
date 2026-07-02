"use client";

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";

type ChartData = Array<{ date: string; [version: string]: number | string }>;

const colors = [
  "#3b82f6",
  "#10b981",
  "#f59e0b",
  "#ef4444",
  "#8b5cf6",
  "#ec4899",
];

export function AdoptionChart({ data }: { data: ChartData }) {
  const versions = Array.from(
    new Set(
      data.flatMap((d) =>
        Object.keys(d).filter((key) => key !== "date")
      )
    )
  );

  return (
    <ResponsiveContainer width="100%" height={300}>
      <LineChart data={data}>
        <CartesianGrid strokeDasharray="3 3" />
        <XAxis dataKey="date" />
        <YAxis />
        <Tooltip />
        <Legend />
        {versions.map((version, idx) => (
          <Line
            key={version}
            type="monotone"
            dataKey={version}
            stroke={colors[idx % colors.length]}
            strokeWidth={2}
          />
        ))}
      </LineChart>
    </ResponsiveContainer>
  );
}
