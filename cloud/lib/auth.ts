import NextAuth from "next-auth";
import GitHub from "next-auth/providers/github";
import { prisma } from "./prisma";

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: [
    GitHub({
      clientId: process.env.GITHUB_ID,
      clientSecret: process.env.GITHUB_SECRET,
    }),
  ],
  callbacks: {
    async signIn({ profile }) {
      if (!profile?.id || !profile?.login) {
        return false;
      }

      const githubId = typeof profile.id === 'string' ? parseInt(profile.id, 10) : profile.id;

      await prisma.user.upsert({
        where: { githubId },
        update: {
          githubLogin: profile.login as string,
          email: profile.email as string | null,
        },
        create: {
          githubId,
          githubLogin: profile.login as string,
          email: profile.email as string | null,
        },
      });

      return true;
    },
    async session({ session, token }) {
      if (token?.sub && session.user) {
        const githubId = parseInt(token.sub, 10);
        const user = await prisma.user.findUnique({
          where: { githubId },
          select: { githubLogin: true, id: true },
        });

        if (user) {
          session.user.githubLogin = user.githubLogin;
          session.user.id = user.id;
        }
      }
      return session;
    },
  },
});
