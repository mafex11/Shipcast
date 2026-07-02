"use server";

import { auth } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { z } from "zod";

const createAppSchema = z.object({
  slug: z.string().regex(/^[a-z0-9-]+$/, "Slug must contain only lowercase letters, numbers, and hyphens"),
  name: z.string().min(1, "Name is required"),
});

export async function createApp(formData: FormData) {
  const session = await auth();
  if (!session?.user?.id) {
    return { error: "Unauthorized" };
  }

  const slug = formData.get("slug") as string;
  const name = formData.get("name") as string;

  const validation = createAppSchema.safeParse({ slug, name });
  if (!validation.success) {
    return { error: validation.error.issues[0].message };
  }

  try {
    await prisma.app.create({
      data: {
        slug: validation.data.slug,
        name: validation.data.name,
        userId: session.user.id,
      },
    });
    return { success: true };
  } catch (error: unknown) {
    if (error && typeof error === "object" && "code" in error && error.code === "P2002") {
      return { error: "An app with this slug already exists" };
    }
    return { error: "Failed to create app" };
  }
}
