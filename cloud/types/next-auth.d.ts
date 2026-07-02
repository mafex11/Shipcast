import "next-auth";

declare module "next-auth" {
  interface Session {
    user: {
      id: string;
      githubLogin: string;
      name?: string | null;
      email?: string | null;
      image?: string | null;
    };
  }
}
